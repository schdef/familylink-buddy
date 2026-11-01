import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../auth/google_sign_in_service.dart';
import '../auth/sign_in_screen.dart';
import '../pairing/pairing_repository.dart';
import '../bedtime/bedtime_schedule_screen.dart';
import '../screenshot/screenshot_screen.dart';
import '../updater/p2p_updater_service.dart';
import 'volume_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class VolumeControlScreen extends StatefulWidget {
  final GoogleSignInAccount? account;
  final PairedDevice device;

  const VolumeControlScreen({
    super.key,
    this.account,
    required this.device,
  });

  @override
  State<VolumeControlScreen> createState() => _VolumeControlScreenState();
}

class _ScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _VolumeControlScreenState extends State<VolumeControlScreen> with SingleTickerProviderStateMixin {
  late VolumeRepository _volumeRepository;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  final Map<String, double> _localValues = {};
  final Map<String, DateTime> _lastSetTimes = {};
  bool _isRefreshing = false;
  Timer? _refreshTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();

    _volumeRepository = Provider.of<VolumeRepository>(context, listen: false);
    _volumeRepository.addListener(_onRepositoryUpdate);
    _volumeRepository.initialize().then((_) {
      _volumeRepository.subscribeToDevice(widget.device.fcmToken);
      _volumeRepository.requestVolumeReport(widget.device.fcmToken);
    });
  }

  void _onRepositoryUpdate() {
    if (mounted) {
      setState(() {
        // Check if we were refreshing and just received a fresh volume report timestamp
        if (_isRefreshing &&
            _volumeRepository.volumeState.timestamp != null &&
            _volumeRepository.volumeState.timestamp!.isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
          _isRefreshing = false;
          _refreshTimeoutTimer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status erfolgreich aktualisiert!'),
              backgroundColor: Color(0xFF10B981),
              duration: Duration(seconds: 2),
            ),
          );
        }

        _localValues.removeWhere((streamName, localVal) {
          int repoVal = -1;
          if (streamName == 'MEDIA') repoVal = _volumeRepository.volumeState.mediaVolume;
          if (streamName == 'RINGTONE') repoVal = _volumeRepository.volumeState.ringtoneVolume;
          if (streamName == 'ALARM') repoVal = _volumeRepository.volumeState.alarmVolume;
          return repoVal == localVal.toInt();
        });
      });
    }
  }

  @override
  void dispose() {
    _refreshTimeoutTimer?.cancel();
    _volumeRepository.removeListener(_onRepositoryUpdate);
    _animController.dispose();
    super.dispose();
  }

  Future<void> _triggerRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    _refreshTimeoutTimer?.cancel();
    _refreshTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isRefreshing) {
        setState(() {
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Fehler beim Aktualisieren: Keine Antwort vom Gerät. Ist das Kind online?',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    });

    await _volumeRepository.requestVolumeReport(widget.device.fcmToken);
  }

  // Using static utility from VolumeRepository instead

  Future<void> _handleSignOut() async {
    final pairingRepo = PairingRepository();
    await pairingRepo.clearPairedDevice();
    await GoogleSignInService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  Widget _buildVolumeSlider({
    required String title,
    required IconData icon,
    required int value,
    required int maxValue,
    required String streamName,
    required ValueChanged<double> onChanged,
  }) {
    final double? localVal = _localValues[streamName];
    final DateTime? lastSet = _lastSetTimes[streamName];
    final bool useLocal = localVal != null &&
        lastSet != null &&
        DateTime.now().difference(lastSet).inSeconds < 3;

    final double displayValue = useLocal ? localVal : (value >= 0 ? value.toDouble() : 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFF6366F1), size: 20),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${displayValue.round()}/$maxValue',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF6366F1),
              inactiveTrackColor: const Color(0xFF334155),
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: displayValue.clamp(0.0, maxValue.toDouble()),
              min: 0,
              max: maxValue.toDouble(),
              divisions: maxValue > 0 ? maxValue : 1,
              onChanged: (val) {
                setState(() {
                  _localValues[streamName] = val;
                  _lastSetTimes[streamName] = DateTime.now();
                });
              },
              onChangeEnd: (val) {
                onChanged(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Lautstärke-Steuerung'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            tooltip: 'Gerät entkoppeln',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Gerät entkoppeln?', style: TextStyle(color: Colors.white)),
                  content: Text(
                    'Möchten Sie das Gerät von ${widget.device.name} wirklich entkoppeln?',
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Abbrechen', style: TextStyle(color: Colors.white)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    TextButton(
                      child: const Text('Entkoppeln', style: TextStyle(color: Color(0xFFEF4444))),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await FirebaseFirestore.instance
                            .collection('pairings')
                            .doc(widget.device.fcmToken)
                            .delete();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${widget.device.name} wurde entkoppelt.')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Abmelden?', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Möchten Sie sich abmelden und die Koppelung zu diesem Gerät aufheben?',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Abmelden', style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _handleSignOut();
                      },
                    ),
                    TextButton(
                      child: const Text('Konto löschen (GDPR)', style: TextStyle(color: Color(0xFFEF4444))),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        try {
                          await FirebaseFunctions.instance.httpsCallable('deleteUserAccount').call();
                        } catch (e) {
                          debugPrint("GDPR delete failed: $e");
                        }
                        _handleSignOut();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<VolumeRepository>(
        builder: (context, repo, child) {
          final isOnline = repo.isConnected &&
              repo.lastSeen != null &&
              DateTime.now().difference(repo.lastSeen!).inMinutes < 2;

          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScrollConfiguration(
              behavior: _ScrollBehavior(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person, color: Color(0xFF6366F1), size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.device.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Text(
                                      isOnline ? 'Verbunden' : 'Offline',
                                      style: TextStyle(
                                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '(${VolumeRepository.getLastSeenText(repo.lastSeen)})',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _isRefreshing
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
                                  onPressed: _triggerRefresh,
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Volume Cards
                    _buildVolumeSlider(
                      title: 'Medien-Lautstärke',
                      icon: Icons.music_note,
                      value: repo.volumeState.mediaVolume,
                      maxValue: repo.volumeState.maxMediaVolume,
                      streamName: 'MEDIA',
                      onChanged: (val) {
                        repo.setVolume(
                          childFcmToken: widget.device.fcmToken,
                          stream: 'MEDIA',
                          level: val.toInt(),
                        );
                      },
                    ),

                    _buildVolumeSlider(
                      title: 'Klingelton',
                      icon: Icons.notifications,
                      value: repo.volumeState.ringtoneVolume,
                      maxValue: repo.volumeState.maxRingtoneVolume,
                      streamName: 'RINGTONE',
                      onChanged: (val) {
                        repo.setVolume(
                          childFcmToken: widget.device.fcmToken,
                          stream: 'RINGTONE',
                          level: val.toInt(),
                        );
                      },
                    ),

                    _buildVolumeSlider(
                      title: 'Wecker-Lautstärke',
                      icon: Icons.alarm,
                      value: repo.volumeState.alarmVolume,
                      maxValue: repo.volumeState.maxAlarmVolume,
                      streamName: 'ALARM',
                      onChanged: (val) {
                        repo.setVolume(
                          childFcmToken: widget.device.fcmToken,
                          stream: 'ALARM',
                          level: val.toInt(),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Global Preset Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              repo.setVolume(
                                childFcmToken: widget.device.fcmToken,
                                stream: 'ALL',
                                level: 0,
                              );
                            },
                            icon: const Icon(Icons.volume_mute, size: 20),
                            label: const Text('Alles stumm'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              repo.setVolume(
                                childFcmToken: widget.device.fcmToken,
                                stream: 'ALL',
                                level: 15,
                              );
                            },
                            icon: const Icon(Icons.volume_up, size: 20),
                            label: const Text('Maximal'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Bedtime Schedule Navigation Card
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BedtimeScheduleScreen(
                              device: widget.device,
                              localIpAddress: repo.localIpAddress,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF1E1B4B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.bedtime_rounded, color: Color(0xFF6366F1), size: 24),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WLAN-Nachtruhe',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Automatische Bettzeit-Sperre & Sofort-Kappung',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Live-Bildschirm & Screenshot-Verlauf Navigation Card
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ScreenshotScreen(
                              device: widget.device,
                              localIpAddress: repo.localIpAddress,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF1E1B4B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.screenshot_monitor_rounded, color: Color(0xFF6366F1), size: 24),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Live-Bildschirm & Screenshot-Verlauf',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Aktuellen Bildschirm abrufen & Verlauf einsehen',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // P2P Wi-Fi Update Trigger Card
                    InkWell(
                      onTap: () {
                        _showP2PUpdateDialog(context, repo.localIpAddress);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.wifi_protected_setup, color: Color(0xFF10B981), size: 24),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'P2P App-Update (WLAN)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Kinder-App direkt im Heimnetzwerk aktualisieren',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showP2PUpdateDialog(BuildContext context, String? localIpAddress) {
    showDialog(
      context: context,
      builder: (ctx) => _P2PUpdateDialog(
        initialLocalIp: localIpAddress,
        childFcmToken: widget.device.fcmToken,
      ),
    );
  }
}

class _P2PUpdateDialog extends StatefulWidget {
  final String? initialLocalIp;
  final String childFcmToken;

  const _P2PUpdateDialog({
    this.initialLocalIp,
    required this.childFcmToken,
  });

  @override
  State<_P2PUpdateDialog> createState() => _P2PUpdateDialogState();
}

class _P2PUpdateDialogState extends State<_P2PUpdateDialog> {
  late TextEditingController _ipController;
  late TextEditingController _pathController;
  bool _isUploading = false;
  double _progress = -1.0;
  String _statusMessage = '';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialLocalIp ?? '');
    _pathController = TextEditingController();
    _checkDefaultApk();
  }

  void _checkDefaultApk() {
    final candidates = [
      '/home/stefanheintz/coding/familylink-buddy/build/child-app-release.apk',
      '/tmp/child-app-release.apk',
      '${Directory.systemTemp.path}/child-update.apk',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        _pathController.text = path;
        break;
      }
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _startP2PUpdate() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _hasError = true;
        _statusMessage = 'Bitte geben Sie die IP-Adresse des Kinder-Geräts ein.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _hasError = false;
      _progress = 0.0;
      _statusMessage = 'Bereite Übertragung vor...';
    });

    try {
      String apkPath = _pathController.text.trim();

      // If user did not provide an existing local path, attempt download from releases metadata
      if (apkPath.isEmpty || !File(apkPath).existsSync()) {
        setState(() {
          _statusMessage = 'Lade neueste Kinder-App von Server...';
        });

        final doc = await FirebaseFirestore.instance
            .collection('app_metadata')
            .doc('releases')
            .get();

        String? downloadUrl;
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data.containsKey('child')) {
            final childData = Map<String, dynamic>.from(data['child']);
            downloadUrl = childData['downloadUrl'] as String?;
          }
        }

        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          final response = await http.get(Uri.parse(downloadUrl));
          if (response.statusCode == 200) {
            final tempFile = File('${Directory.systemTemp.path}/child-update.apk');
            await tempFile.writeAsBytes(response.bodyBytes);
            apkPath = tempFile.path;
          } else {
            throw Exception('Konnte APK nicht herunterladen (Status ${response.statusCode})');
          }
        } else {
          if (apkPath.isEmpty) {
            throw Exception('Keine APK-Datei angegeben und kein Download im Release-Kanal verfügbar.');
          }
        }
      }

      setState(() {
        _statusMessage = 'Sende APK per WLAN an $ip:8085...';
      });

      final updater = P2PUpdaterService();
      await updater.pushUpdateToChild(
        childLocalIp: ip,
        apkFilePath: apkPath,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = 'WLAN-Übertragung: ${(p * 100).toInt()}%';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          _progress = 1.0;
          _statusMessage = 'Update erfolgreich übertragen! Installation gestartet.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _hasError = true;
          _statusMessage = 'Fehler: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.wifi_protected_setup, color: Color(0xFF10B981)),
          SizedBox(width: 10),
          Text(
            'P2P Wi-Fi Update',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aktualisiere die Kinder-App blitzschnell direkt über das lokale Heimnetzwerk ohne Internet-Download auf dem Zielgerät.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),

            const Text(
              'IP-Adresse des Kindes (Port 8085)',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ipController,
              enabled: !_isUploading,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: 'z.B. 192.168.1.100',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.lan, color: Color(0xFF6366F1), size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(height: 14),

            const Text(
              'APK-Pfad (optional)',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _pathController,
              enabled: !_isUploading,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: 'Standard: Automatisch aus Release-Kanal',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.folder_zip_outlined, color: Color(0xFF94A3B8), size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),

            if (_progress >= 0.0) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: const Color(0xFF0F172A),
                color: _hasError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],

            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                style: TextStyle(
                  color: _hasError
                      ? const Color(0xFFEF4444)
                      : (_progress >= 1.0 ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Schließen', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
        ElevatedButton.icon(
          onPressed: _isUploading ? null : _startP2PUpdate,
          icon: _isUploading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(_isUploading ? 'Übertrage...' : 'Update übertragen'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}
