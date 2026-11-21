import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../l10n/app_strings.dart';
import '../pairing/pairing_repository.dart';
import 'p2p_updater_service.dart';
import 'updater_service.dart';

class UpdateDialog extends StatefulWidget {
  final String? childIp;
  final http.Client? client;
  final VoidCallback? onOpenManualP2p;

  const UpdateDialog({
    super.key,
    this.childIp,
    this.client,
    this.onOpenManualP2p,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  ReleaseInfo? _releaseInfo;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isActionRunning = false;
  double _progress = -1.0;
  String _statusMessage = '';
  late final TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.childIp ?? '');
    _initChildIpAndFetchRelease();
  }

  Future<void> _initChildIpAndFetchRelease() async {
    if (_ipController.text.trim().isEmpty) {
      try {
        final devices = await PairingRepository().loadAllPairedDevices();
        if (devices.isNotEmpty && mounted) {
          final firstIp = devices.first.localIpAddress;
          if (firstIp != null && firstIp.isNotEmpty) {
            _ipController.text = firstIp;
          }
        }
      } catch (_) {}
    }
    await _fetchRelease();
  }

  Future<void> _fetchRelease() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final info = await UpdaterService.fetchLatestRelease(client: widget.client);
      if (mounted) {
        setState(() {
          _releaseInfo = info;
          _isLoading = false;
          if (info == null) {
            final strings = AppStrings.of(context);
            _errorMessage = strings.updateError;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final strings = AppStrings.of(context);
        setState(() {
          _isLoading = false;
          _errorMessage = strings.updateError;
        });
      }
    }
  }

  Future<void> _updateParentApp() async {
    final strings = AppStrings.of(context);
    final parentUrl = _releaseInfo?.parentApkUrl;
    if (parentUrl == null) return;

    if (kIsWeb) {
      setState(() {
        _statusMessage = strings.webManualDownloadNotice;
      });
      return;
    }

    setState(() {
      _isActionRunning = true;
      _progress = 0.0;
      _statusMessage = strings.downloadingUpdate(0);
    });

    try {
      final success = await UpdaterService.downloadAndInstallParentApk(
        apkUrl: parentUrl,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = strings.downloadingUpdate((p * 100).toInt());
            });
          }
        },
        client: widget.client,
      );

      if (mounted) {
        setState(() {
          _isActionRunning = false;
          _statusMessage = success ? strings.parentAppUpdated : strings.updateError;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionRunning = false;
          _statusMessage = strings.updateError;
        });
      }
    }
  }

  Future<void> _updateChildTablet() async {
    final strings = AppStrings.of(context);
    final childUrl = _releaseInfo?.childApkUrl;
    if (childUrl == null) return;

    final targetIp = _ipController.text.trim();
    if (targetIp.isEmpty) {
      setState(() {
        _statusMessage = strings.enterChildIp;
      });
      return;
    }

    if (kIsWeb) {
      setState(() {
        _statusMessage = strings.webManualDownloadNotice;
      });
      return;
    }

    setState(() {
      _isActionRunning = true;
      _progress = 0.0;
      _statusMessage = strings.downloadingUpdate(0);
    });

    try {
      final apkPath = await UpdaterService.downloadChildApk(
        apkUrl: childUrl,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p * 0.5;
              _statusMessage = strings.downloadingUpdate((p * 100).toInt());
            });
          }
        },
        client: widget.client,
      );

      if (apkPath == null) {
        if (mounted) {
          setState(() {
            _isActionRunning = false;
            _statusMessage = strings.updateError;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _statusMessage = strings.sendingApkWifi(targetIp);
        });
      }

      final p2pService = P2PUpdaterService(client: widget.client);
      final pushSuccess = await p2pService.pushUpdateToChild(
        childLocalIp: targetIp,
        apkFilePath: apkPath,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = 0.5 + p * 0.5;
              _statusMessage = strings.wifiTransferProgress((p * 100).toInt());
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isActionRunning = false;
          _statusMessage = pushSuccess ? strings.pushedToChildSuccess : strings.updateError;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionRunning = false;
          _statusMessage = strings.updateError;
        });
      }
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isNewer = _releaseInfo != null &&
        UpdaterService.isNewerVersion(_releaseInfo!.tagName, UpdaterService.currentVersion);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actionsOverflowButtonSpacing: 8,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded, color: Color(0xFF818CF8), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              strings.updatesTitle,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Version Badges Row
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      strings.currentVersionLabel(UpdaterService.currentVersion),
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_releaseInfo != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isNewer
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                            : const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isNewer
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                              : const Color(0xFF10B981).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        strings.latestVersionLabel(_releaseInfo!.tagName),
                        style: TextStyle(
                          color: isNewer ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF6366F1)),
                      const SizedBox(height: 12),
                      Text(strings.checkingForUpdates, style: const TextStyle(color: Color(0xFF94A3B8))),
                    ],
                  ),
                )
              else if (_errorMessage != null && _releaseInfo == null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                        onPressed: _fetchRelease,
                        tooltip: strings.checkForUpdates,
                      ),
                    ],
                  ),
                )
              else if (_releaseInfo != null) ...[
                // Update Status Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isNewer
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                        : const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isNewer
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                          : const Color(0xFF10B981).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isNewer ? Icons.new_releases_outlined : Icons.check_circle_outline,
                        color: isNewer ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isNewer ? strings.updateAvailable(_releaseInfo!.tagName) : strings.upToDate,
                          style: TextStyle(
                            color: isNewer ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Release Notes
                if (_releaseInfo!.releaseNotes.trim().isNotEmpty) ...[
                  Text(
                    strings.releaseNotes,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _releaseInfo!.releaseNotes.trim(),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Web Platform Notice
                if (kIsWeb) ...[
                  Text(
                    strings.webManualDownloadNotice,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _releaseInfo!.parentApkUrl ?? _releaseInfo!.htmlUrl,
                    style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, decoration: TextDecoration.underline),
                  ),
                  const SizedBox(height: 12),
                ],

                // Child IP Field
                TextField(
                  controller: _ipController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: strings.childIpLabel,
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    hintText: strings.childIpHint,
                    hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Progress Bar
                if (_isActionRunning || _progress >= 0) ...[
                  LinearProgressIndicator(
                    value: _progress >= 0 ? _progress : null,
                    backgroundColor: const Color(0xFF334155),
                    color: const Color(0xFF6366F1),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 8),
                ],

                // Status Message
                if (_statusMessage.isNotEmpty)
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),

                if (widget.onOpenManualP2p != null && !_isActionRunning) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey('btn_manual_p2p_transfer'),
                      icon: const Icon(Icons.file_upload_outlined, size: 16, color: Color(0xFF94A3B8)),
                      label: Text(strings.selectApkButton, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenManualP2p!();
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_releaseInfo != null && !_isActionRunning) ...[
          ElevatedButton.icon(
            key: const ValueKey('btn_update_parent_app'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.system_update_rounded, size: 16),
            label: Text(strings.updateParentApp, style: const TextStyle(fontSize: 12)),
            onPressed: _updateParentApp,
          ),
          ElevatedButton.icon(
            key: const ValueKey('btn_update_child_app'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.tablet_android_rounded, size: 16),
            label: Text(strings.updateChildApp, style: const TextStyle(fontSize: 12)),
            onPressed: _updateChildTablet,
          ),
        ],
        TextButton(
          child: Text(strings.cancel, style: const TextStyle(color: Color(0xFF94A3B8))),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
