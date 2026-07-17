import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../auth/google_sign_in_service.dart';
import '../auth/sign_in_screen.dart';
import '../pairing/pairing_repository.dart';
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
