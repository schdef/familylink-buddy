import 'package:flutter/material.dart';
import 'pairing_screen.dart';
import 'pairing_repository.dart';
import '../volume/volume_control_screen.dart';
import '../time_bank/time_bank_screen.dart';
import '../comms/comms_screen.dart';
import '../updater/updater_service.dart';
import '../l10n/app_strings.dart';

class DeviceListScreen extends StatefulWidget {
  final PairingRepository? repository;

  const DeviceListScreen({super.key, this.repository});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late final PairingRepository _repository;
  List<PairedDevice> _devices = [];
  bool _isLoading = true;
  final Map<String, bool?> _deviceOnlineState = {};

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PairingRepository();
    _loadDevices();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdaterService.checkForUpdates(context);
    });
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final devices = await _repository.loadPairedDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _isLoading = false;
      });

      for (final device in devices) {
        final ip = (device.localIpAddress != null && device.localIpAddress!.isNotEmpty)
            ? device.localIpAddress
            : (device.fcmToken == 'emulator' ? '10.0.2.2' : null);
        if (ip != null && ip.isNotEmpty) {
          _deviceOnlineState[device.id] = null; // checking
          _repository
              .verifyDeviceConnectivity(ip, device.port, device.token,
                  timeout: const Duration(seconds: 2))
              .then((isOnline) {
            if (mounted) {
              setState(() {
                _deviceOnlineState[device.id] = isOnline;
              });
            }
          });
        } else {
          _deviceOnlineState[device.id] = false;
        }
      }
    }
  }

  Future<void> _unpairDevice(PairedDevice device) async {
    final strings = context.strings;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(strings.unpairDeviceTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          strings.unpairDeviceConfirm(device.name),
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            child: Text(strings.cancel, style: const TextStyle(color: Colors.white)),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          TextButton(
            child: Text(strings.unpair, style: const TextStyle(color: Color(0xFFEF4444))),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repository.clearPairedDevice();
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.deviceUnpaired(device.name))),
        );
      }
    }
  }

  void _showAppSettings() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final strings = AppStrings.of(dialogCtx);
          final currentCode = AppStrings.manualLocale?.languageCode;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Row(
              children: [
                const Icon(Icons.settings, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Text(strings.appSettingsTitle, style: const TextStyle(color: Colors.white)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.appEdition,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(strings.appVersion('1.1.2'), style: const TextStyle(color: Color(0xFF94A3B8))),
                  const SizedBox(height: 4),
                  Text(strings.appArchitecture, style: const TextStyle(color: Color(0xFF10B981))),
                  const SizedBox(height: 4),
                  Text(strings.appCloudNotice, style: const TextStyle(color: Color(0xFF94A3B8))),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF334155)),
                  const SizedBox(height: 8),
                  Text(
                    strings.language,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: currentCode,
                        dropdownColor: const Color(0xFF1E293B),
                        isExpanded: true,
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(strings.systemDefault, style: const TextStyle(color: Colors.white)),
                          ),
                          DropdownMenuItem<String?>(
                            value: 'en',
                            child: Text(strings.english, style: const TextStyle(color: Colors.white)),
                          ),
                          DropdownMenuItem<String?>(
                            value: 'de',
                            child: Text(strings.german, style: const TextStyle(color: Colors.white)),
                          ),
                        ],
                        onChanged: (newCode) async {
                          await AppStrings.setSavedLocale(newCode);
                          setDialogState(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: Text(strings.close, style: const TextStyle(color: Color(0xFF6366F1))),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          );
        },
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
            Text(strings.myChildren),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
              ),
              child: Text(
                strings.lanLocal,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF34D399),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            onPressed: _loadDevices,
            tooltip: strings.refreshTooltip,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
            onPressed: _showAppSettings,
            tooltip: strings.settingsTooltip,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : _devices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline, color: Color(0xFF475569), size: 80),
                        const SizedBox(height: 24),
                        Text(
                          strings.noChildrenPaired,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          strings.noChildrenPairedDesc,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PairingScreen(),
                              ),
                            );
                            _loadDevices();
                          },
                          icon: const Icon(Icons.add),
                          label: Text(strings.pairDevice),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Card(
                      color: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: const Color(0xFF334155).withValues(alpha: 0.5)),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VolumeControlScreen(
                                device: device,
                              ),
                            ),
                          ).then((_) => _loadDevices());
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.child_care,
                                  color: Color(0xFF6366F1),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _buildDeviceStatus(device, strings),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF6366F1),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(Icons.timer, size: 14),
                                          label: Text(strings.timeBankButton, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => TimeBankScreen(
                                                  device: device,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF818CF8),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(Icons.mic, size: 14),
                                          label: Text(strings.commsButton, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => CommsScreen(
                                                  device: device,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                tooltip: strings.unpairTooltip,
                                onPressed: () => _unpairDevice(device),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_ios,
                                color: Color(0xFF475569),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _devices.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PairingScreen(),
                  ),
                );
                _loadDevices();
              },
              icon: const Icon(Icons.add),
              label: Text(strings.addChild),
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
    );
  }

  Widget _buildDeviceStatus(PairedDevice device, AppStrings strings) {
    final ip = (device.localIpAddress != null && device.localIpAddress!.isNotEmpty)
        ? device.localIpAddress
        : (device.fcmToken == 'emulator' ? '10.0.2.2' : null);
    final isOnline = _deviceOnlineState[device.id];

    final String ipLabel;
    if (ip != null && ip.isNotEmpty) {
      ipLabel = (device.fcmToken == 'emulator' && (device.localIpAddress == null || device.localIpAddress!.isEmpty))
          ? 'Emulator (10.0.2.2)'
          : 'LAN ($ip)';
    } else {
      ipLabel = strings.localLan;
    }

    final Color statusColor;
    final String statusText;
    final Widget dotWidget;

    if (isOnline == true) {
      statusColor = const Color(0xFF10B981);
      statusText = '${strings.online} • $ipLabel';
      dotWidget = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
      );
    } else if (isOnline == false) {
      statusColor = const Color(0xFFEF4444);
      statusText = '${strings.offline} • $ipLabel';
      dotWidget = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      );
    } else {
      // isOnline == null (Checking)
      statusColor = const Color(0xFFF59E0B);
      statusText = '${strings.checking} • $ipLabel';
      dotWidget = const SizedBox(
        width: 8,
        height: 8,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Color(0xFFF59E0B),
        ),
      );
    }

    return Row(
      children: [
        dotWidget,
        const SizedBox(width: 6),
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
