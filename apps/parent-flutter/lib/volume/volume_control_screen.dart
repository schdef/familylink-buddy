import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import '../pairing/pairing_screen.dart';
import '../pairing/lan_discovery_service.dart';
import '../pairing/device_list_screen.dart';
import '../bedtime/bedtime_schedule_screen.dart';
import '../screenshot/screenshot_screen.dart';
import '../app_limits/app_limits_screen.dart';
import '../comms/calls_screen.dart';
import '../comms/chats_screen.dart';
import '../updater/p2p_updater_service.dart';
import '../updater/updater_service.dart';
import '../l10n/app_strings.dart';
import 'volume_repository.dart';

class VolumeControlScreen extends StatefulWidget {
  final PairedDevice device;

  const VolumeControlScreen({
    super.key,
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
  late PairedDevice _currentDevice;
  List<PairedDevice> _allDevices = [];

  @override
  void initState() {
    super.initState();
    _currentDevice = widget.device;
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
      _volumeRepository.subscribeToDevice(
        _currentDevice.fcmToken,
        ipAddress: _currentDevice.localIpAddress,
        deviceId: _currentDevice.id,
        pairingRepo: PairingRepository(),
        discoveryService: LanDiscoveryService(),
      );
      _volumeRepository.requestVolumeReport(_currentDevice.fcmToken);
    });
    _loadAllDevices();
  }

  Future<void> _loadAllDevices() async {
    final devices = await PairingRepository().loadAllPairedDevices();
    if (mounted) {
      setState(() {
        _allDevices = devices;
        final idx = devices.indexWhere((d) => d.id == _currentDevice.id);
        if (idx >= 0) {
          _currentDevice = devices[idx];
        }
      });
    }
  }

  void _switchDevice(PairedDevice newDevice) {
    if (newDevice.id == _currentDevice.id && newDevice.token == _currentDevice.token) return;
    setState(() {
      _currentDevice = newDevice;
      _localValues.clear();
      _lastSetTimes.clear();
    });
    _volumeRepository.subscribeToDevice(
      newDevice.fcmToken,
      ipAddress: newDevice.localIpAddress,
      deviceId: newDevice.id,
      pairingRepo: PairingRepository(),
      discoveryService: LanDiscoveryService(),
    );
    _volumeRepository.requestVolumeReport(newDevice.fcmToken);
    PairingRepository().savePairedDevice(newDevice);
  }

  void _openAddKid() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PairingScreen(),
      ),
    ).then((_) {
      _loadAllDevices();
    });
  }

  void _onRepositoryUpdate() {
    if (mounted) {
      final strings = context.strings;
      setState(() {
        // Check if we were refreshing and just received a fresh volume report timestamp
        if (_isRefreshing &&
            _volumeRepository.volumeState.timestamp != null &&
            _volumeRepository.volumeState.timestamp!.isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
          _isRefreshing = false;
          _refreshTimeoutTimer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.statusUpdated),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        _localValues.removeWhere((streamName, localVal) {
          int repoVal = -1;
          if (streamName == 'MEDIA') repoVal = _volumeRepository.volumeState.mediaVolume;
          if (streamName == 'RINGTONE') repoVal = _volumeRepository.volumeState.ringtoneVolume;
          if (streamName == 'ALARM') repoVal = _volumeRepository.volumeState.alarmVolume;
          return repoVal >= 0 && repoVal == localVal.round();
        });
      });
    }
  }

  @override
  void dispose() {
    _refreshTimeoutTimer?.cancel();
    _volumeRepository.removeListener(_onRepositoryUpdate);
    _volumeRepository.stopPolling();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _triggerRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    final strings = context.strings;
    _refreshTimeoutTimer?.cancel();
    _refreshTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isRefreshing) {
        setState(() {
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.updateErrorNoResponse,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    });

    await _volumeRepository.requestVolumeReport(_currentDevice.fcmToken);
  }

  // Using static utility from VolumeRepository instead

  Future<void> _handleUnpair() async {
    final pairingRepo = PairingRepository();
    await pairingRepo.removePairedDevice(_currentDevice.id);
    final remaining = await pairingRepo.loadAllPairedDevices();
    if (remaining.isNotEmpty) {
      if (mounted) {
        _switchDevice(remaining.first);
        _loadAllDevices();
      }
    } else {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DeviceListScreen()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildActiveAudioCard(BuildContext context, VolumeRepository repo) {
    final strings = context.strings;
    return Container(
      key: const ValueKey('active_audio_card'),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.15),
            const Color(0xFF1E293B).withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.graphic_eq,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (repo.volumeState.mediaTitle != null && repo.volumeState.mediaTitle!.isNotEmpty)
                          ? repo.volumeState.mediaTitle!
                          : strings.audioPlayingSpotify,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (repo.volumeState.mediaArtist != null && repo.volumeState.mediaArtist!.isNotEmpty)
                          ? '${repo.volumeState.mediaArtist} • ${strings.activeMediaPlayback}'
                          : strings.activeMediaPlayback,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            key: const ValueKey('stop_audio_button'),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final success = await repo.stopAudioPlayback(childToken: _currentDevice.fcmToken);
              if (!context.mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(strings.playbackStopped),
                    backgroundColor: const Color(0xFF10B981),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(strings.errorStoppingPlayback),
                    backgroundColor: const Color(0xFFEF4444),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.pause_circle_filled, size: 20),
            label: Text(strings.stopPlayback),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
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
        DateTime.now().difference(lastSet).inSeconds < 8;

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

  Widget _buildQuickActionBar(BuildContext context, VolumeRepository repo) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                strings.quickAccess,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            // 1. App-Limits & Sperren
            Expanded(
              child: _buildQuickActionCard(
                key: const ValueKey('action_app_limits_button'),
                icon: Icons.timer_outlined,
                label: strings.quickActionAppLimits,
                accentColor: const Color(0xFFEC4899),
                onTap: () {
                  final effectiveIp = (repo.localIpAddress != null && repo.localIpAddress!.isNotEmpty)
                      ? repo.localIpAddress
                      : _currentDevice.localIpAddress;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppLimitsScreen(
                        device: _currentDevice,
                        localIpAddress: effectiveIp,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),

            // 2. WLAN-Nachtruhe
            Expanded(
              child: _buildQuickActionCard(
                icon: Icons.bedtime_rounded,
                label: strings.quickActionBedtime,
                accentColor: const Color(0xFF8B5CF6),
                onTap: () {
                  final effectiveIp = (repo.localIpAddress != null && repo.localIpAddress!.isNotEmpty)
                      ? repo.localIpAddress
                      : _currentDevice.localIpAddress;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BedtimeScheduleScreen(
                        device: _currentDevice,
                        localIpAddress: effectiveIp,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // 3. Live-Screenshot
            Expanded(
              child: _buildQuickActionCard(
                icon: Icons.camera_alt_rounded,
                label: strings.quickActionScreenshot,
                accentColor: const Color(0xFF06B6D4),
                onTap: () {
                  final effectiveIp = (repo.localIpAddress != null && repo.localIpAddress!.isNotEmpty)
                      ? repo.localIpAddress
                      : _currentDevice.localIpAddress;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScreenshotScreen(
                        device: _currentDevice,
                        localIpAddress: effectiveIp,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),

            // 4. WLAN-Update
            Expanded(
              child: _buildQuickActionCard(
                icon: Icons.wifi_protected_setup_rounded,
                label: strings.quickActionUpdate,
                accentColor: const Color(0xFF10B981),
                onTap: () {
                  final effectiveIp = (repo.localIpAddress != null && repo.localIpAddress!.isNotEmpty)
                      ? repo.localIpAddress
                      : _currentDevice.localIpAddress;
                  UpdaterService.showUpdateDialog(
                    context,
                    childIp: effectiveIp,
                    onOpenManualP2p: () => _showP2PUpdateDialog(context, effectiveIp),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // 5. Call History
            Expanded(
              child: _buildQuickActionCard(
                key: const ValueKey('action_calls_button'),
                icon: Icons.phone_in_talk_rounded,
                label: strings.quickActionCalls,
                accentColor: const Color(0xFFF59E0B),
                onTap: () {
                  final effectiveIp = (repo.localIpAddress != null && repo.localIpAddress!.isNotEmpty)
                      ? repo.localIpAddress
                      : _currentDevice.localIpAddress;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CallsScreen(
                        device: _currentDevice,
                        localIpAddress: effectiveIp,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),

            // 6. Chat Messages
            Expanded(
              child: _buildQuickActionCard(
                key: const ValueKey('action_chats_button'),
                icon: Icons.chat_bubble_outline_rounded,
                label: strings.quickActionChats,
                accentColor: const Color(0xFF14B8A6),
                onTap: () {
                  final effectiveIp = (repo.localIpAddress != null && repo.localIpAddress!.isNotEmpty)
                      ? repo.localIpAddress
                      : _currentDevice.localIpAddress;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatsScreen(
                        device: _currentDevice,
                        localIpAddress: effectiveIp,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    Key? key,
    required IconData icon,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.12),
            const Color(0xFF1E293B).withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withOpacity(0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: accentColor.withOpacity(0.2),
          highlightColor: accentColor.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.volumeControlTitle),
            const SizedBox(width: 8),
            Container(
              key: const ValueKey('app_version_badge'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
              ),
              child: Text(
                'v${UpdaterService.currentVersion}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF818CF8),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          if (_allDevices.length > 1)
            PopupMenuButton<PairedDevice>(
              key: const ValueKey('btn_switch_kid'),
              icon: const Icon(Icons.people_alt_outlined, color: Color(0xFF818CF8)),
              tooltip: strings.switchKid,
              onSelected: _switchDevice,
              itemBuilder: (context) => _allDevices.map((d) {
                final isSelected = d.deviceId == _currentDevice.deviceId;
                return PopupMenuItem<PairedDevice>(
                  value: d,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? const Color(0xFF10B981) : const Color(0xFF64748B),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          d.name,
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          IconButton(
            key: const ValueKey('btn_app_updates'),
            icon: const Icon(Icons.system_update_rounded, color: Color(0xFF818CF8)),
            tooltip: strings.updatesTitle,
            onPressed: () {
              final effectiveIp = (_volumeRepository.localIpAddress != null && _volumeRepository.localIpAddress!.isNotEmpty)
                  ? _volumeRepository.localIpAddress
                  : _currentDevice.localIpAddress;
              UpdaterService.showUpdateDialog(
                context,
                childIp: effectiveIp,
                onOpenManualP2p: () => _showP2PUpdateDialog(context, effectiveIp),
              );
            },
          ),
          IconButton(
            key: const ValueKey('btn_add_kid'),
            icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF818CF8)),
            tooltip: strings.addKid,
            onPressed: _openAddKid,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            tooltip: strings.unpairTooltip,
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: Text(strings.unpairDeviceTitle, style: const TextStyle(color: Colors.white)),
                  content: Text(
                    strings.unpairDeviceConfirm(_currentDevice.name),
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  actions: [
                    TextButton(
                      child: Text(strings.cancel, style: const TextStyle(color: Colors.white)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    TextButton(
                      child: Text(strings.unpair, style: const TextStyle(color: Color(0xFFEF4444))),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final name = _currentDevice.name;
                        await _handleUnpair();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.deviceUnpaired(name))),
                          );
                        }
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
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
                        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
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
                              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person, color: Color(0xFF6366F1), size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _currentDevice.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_allDevices.length > 1) ...[
                                      const SizedBox(width: 8),
                                      PopupMenuButton<PairedDevice>(
                                        key: const ValueKey('header_switch_kid'),
                                        tooltip: strings.switchKid,
                                        onSelected: _switchDevice,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                strings.switchKid,
                                                style: const TextStyle(
                                                  color: Color(0xFF818CF8),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.arrow_drop_down, color: Color(0xFF818CF8), size: 16),
                                            ],
                                          ),
                                        ),
                                        itemBuilder: (context) => _allDevices.map((d) {
                                          final isSelected = d.deviceId == _currentDevice.deviceId;
                                          return PopupMenuItem<PairedDevice>(
                                            value: d,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    d.name,
                                                    style: TextStyle(
                                                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
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
                                      isOnline ? strings.connected : strings.offline,
                                      style: TextStyle(
                                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '(${VolumeRepository.getLastSeenText(repo.lastSeen, strings: strings)})',
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
                    const SizedBox(height: 24),

                    // Quick Access Action Bar
                    _buildQuickActionBar(context, repo),

                    const SizedBox(height: 28),

                    // Active Audio Card
                    if (repo.volumeState.isMusicActive)
                      _buildActiveAudioCard(context, repo),

                    // Volume Cards
                    _buildVolumeSlider(
                      title: strings.mediaVolume,
                      icon: Icons.music_note,
                      value: repo.volumeState.mediaVolume,
                      maxValue: repo.volumeState.maxMediaVolume,
                      streamName: 'MEDIA',
                      onChanged: (val) async {
                        final success = await repo.setVolume(
                          childFcmToken: _currentDevice.fcmToken,
                          stream: 'MEDIA',
                          level: val.round(),
                        );
                        if (!mounted) return;
                        if (success) {
                          setState(() {
                            _localValues['MEDIA'] = val;
                            _lastSetTimes['MEDIA'] = DateTime.now();
                          });
                        } else {
                          setState(() {
                            _localValues.remove('MEDIA');
                            _lastSetTimes.remove('MEDIA');
                          });
                        }
                      },
                    ),

                    _buildVolumeSlider(
                      title: strings.ringtoneVolume,
                      icon: Icons.notifications,
                      value: repo.volumeState.ringtoneVolume,
                      maxValue: repo.volumeState.maxRingtoneVolume,
                      streamName: 'RINGTONE',
                      onChanged: (val) async {
                        final success = await repo.setVolume(
                          childFcmToken: _currentDevice.fcmToken,
                          stream: 'RINGTONE',
                          level: val.round(),
                        );
                        if (!mounted) return;
                        if (success) {
                          setState(() {
                            _localValues['RINGTONE'] = val;
                            _lastSetTimes['RINGTONE'] = DateTime.now();
                          });
                        } else {
                          setState(() {
                            _localValues.remove('RINGTONE');
                            _lastSetTimes.remove('RINGTONE');
                          });
                        }
                      },
                    ),

                    _buildVolumeSlider(
                      title: strings.alarmVolume,
                      icon: Icons.alarm,
                      value: repo.volumeState.alarmVolume,
                      maxValue: repo.volumeState.maxAlarmVolume,
                      streamName: 'ALARM',
                      onChanged: (val) async {
                        final success = await repo.setVolume(
                          childFcmToken: _currentDevice.fcmToken,
                          stream: 'ALARM',
                          level: val.round(),
                        );
                        if (!mounted) return;
                        if (success) {
                          setState(() {
                            _localValues['ALARM'] = val;
                            _lastSetTimes['ALARM'] = DateTime.now();
                          });
                        } else {
                          setState(() {
                            _localValues.remove('ALARM');
                            _lastSetTimes.remove('ALARM');
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 24),

                    // Global Preset Action Buttons (Mute All)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('btn_mute_all'),
                        onPressed: () async {
                          final now = DateTime.now();
                          setState(() {
                            _localValues['MEDIA'] = 0;
                            _localValues['RINGTONE'] = 0;
                            _localValues['ALARM'] = 0;
                            _lastSetTimes['MEDIA'] = now;
                            _lastSetTimes['RINGTONE'] = now;
                            _lastSetTimes['ALARM'] = now;
                          });
                          final success = await repo.setVolume(
                            childFcmToken: _currentDevice.fcmToken,
                            stream: 'ALL',
                            level: 0,
                          );
                          if (!mounted) return;
                          if (!success) {
                            setState(() {
                              _localValues.clear();
                              _lastSetTimes.clear();
                            });
                          }
                        },
                        icon: const Icon(Icons.volume_mute, size: 20),
                        label: Text(strings.muteAll),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
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
        childFcmToken: _currentDevice.fcmToken,
        authToken: _currentDevice.token,
      ),
    );
  }
}

class _P2PUpdateDialog extends StatefulWidget {
  final String? initialLocalIp;
  final String childFcmToken;
  final String? authToken;

  const _P2PUpdateDialog({
    this.initialLocalIp,
    required this.childFcmToken,
    this.authToken,
  });

  @override
  State<_P2PUpdateDialog> createState() => _P2PUpdateDialogState();
}

class _P2PUpdateDialogState extends State<_P2PUpdateDialog> {
  late TextEditingController _ipController;
  late TextEditingController _pathController;
  bool _isUploading = false;
  bool _isPicking = false;
  double _progress = -1.0;
  String _statusMessage = '';
  bool _hasError = false;
  String? _selectedFileName;
  int? _selectedFileSize;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialLocalIp ?? '');
    _pathController = TextEditingController();
    _checkDefaultApk();
  }

  void _checkDefaultApk() {
    if (kIsWeb) return;
    final candidates = [
      'build/child-app-release.apk',
      '/tmp/child-app-release.apk',
      '${Directory.systemTemp.path}/child-update.apk',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        _pathController.text = path;
        _selectedFileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'child-update.apk';
        _selectedFileSize = file.lengthSync();
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

  String _formatFileSize(int? bytes, AppStrings strings) {
    if (bytes == null || bytes <= 0) return strings.unknownSize;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickApkFile() async {
    final strings = context.strings;
    if (kIsWeb) {
      setState(() {
        _hasError = true;
        _statusMessage = 'P2P APK update is only supported on Android / desktop app.';
      });
      return;
    }
    setState(() {
      _isPicking = true;
      _hasError = false;
    });

    try {
      final updater = P2PUpdaterService();
      final result = await updater.pickApkFile();
      if (result != null) {
        final path = result['path'] as String?;
        final name = result['name'] as String?;
        final size = result['size'] as int?;

        if (path != null && path.isNotEmpty) {
          setState(() {
            _pathController.text = path;
            _selectedFileName = name ?? (File(path).existsSync() ? File(path).uri.pathSegments.last : 'update.apk');
            _selectedFileSize = size ?? (File(path).existsSync() ? File(path).lengthSync() : null);
            _statusMessage = strings.apkSelected(_selectedFileName!, _formatFileSize(_selectedFileSize, strings));
          });
        }
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _statusMessage = strings.filePickError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _startP2PUpdate() async {
    final strings = context.strings;
    if (kIsWeb) {
      setState(() {
        _hasError = true;
        _statusMessage = 'P2P APK update is only supported on Android / desktop app.';
      });
      return;
    }
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _hasError = true;
        _statusMessage = strings.enterChildIp;
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _hasError = false;
      _progress = 0.0;
      _statusMessage = strings.preparingTransfer;
    });

    try {
      String apkPath = _pathController.text.trim();

      if (apkPath.isEmpty || !File(apkPath).existsSync()) {
        throw Exception(strings.noValidApk);
      }

      setState(() {
        _statusMessage = strings.sendingApkWifi(ip);
      });

      final updater = P2PUpdaterService();
      await updater.pushUpdateToChild(
        childLocalIp: ip,
        apkFilePath: apkPath,
        authToken: widget.authToken,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = strings.wifiTransferProgress((p * 100).toInt());
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          _progress = 1.0;
          _statusMessage = strings.updateSuccess;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _hasError = true;
          _statusMessage = '${strings.errorPrefix}$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.wifi_protected_setup, color: Color(0xFF10B981)),
          const SizedBox(width: 10),
          Text(
            strings.p2pUpdateTitle,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.p2pUpdateDesc,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),

            Text(
              strings.childIpLabel,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ipController,
              enabled: !_isUploading,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: strings.childIpHint,
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

            Text(
              strings.apkFileLabel,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _pathController,
              enabled: !_isUploading && !_isPicking,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: strings.apkFileHint,
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.folder_zip_outlined, color: Color(0xFF94A3B8), size: 18),
                suffixIcon: IconButton(
                  tooltip: strings.selectApkTooltip,
                  icon: _isPicking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                        )
                      : const Icon(Icons.file_open, color: Color(0xFF38BDF8), size: 20),
                  onPressed: _isUploading || _isPicking ? null : _pickApkFile,
                ),
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
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading || _isPicking ? null : _pickApkFile,
                icon: const Icon(Icons.add_to_drive, size: 18, color: Color(0xFF38BDF8)),
                label: Text(
                  _isPicking ? strings.selectingFile : strings.selectApkButton,
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
                  backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            if (_selectedFileName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_selectedFileName (${_formatFileSize(_selectedFileSize, strings)})',
                        style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

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
          child: Text(strings.close, style: const TextStyle(color: Color(0xFF94A3B8))),
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
          label: Text(_isUploading ? strings.transferring : strings.transferUpdate),
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
