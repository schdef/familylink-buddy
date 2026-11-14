import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import '../volume/volume_repository.dart';
import 'screenshot_model.dart';
import 'screenshot_repository.dart';
import '../l10n/app_strings.dart';

class ScreenshotScreen extends StatefulWidget {
  final PairedDevice device;
  final String? localIpAddress;

  const ScreenshotScreen({
    super.key,
    required this.device,
    this.localIpAddress,
  });

  @override
  State<ScreenshotScreen> createState() => _ScreenshotScreenState();
}

class _ScreenshotScreenState extends State<ScreenshotScreen> {
  bool _isClosingApp = false;
  bool _isLockingScreen = false;
  bool _isDeletingAll = false;
  String? _deletingScreenshotId;
  String _cameraFacing = 'front';
  bool _isCapturingCamera = false;
  bool _isCapturingScreenshot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final repo = Provider.of<ScreenshotRepository>(context, listen: false);
        repo.subscribeToHistory(widget.device.fcmToken, localIpAddress: widget.localIpAddress);
      }
    });
  }

  Uint8List? _safeDecodeBase64(String base64Str) {
    if (base64Str.trim().isEmpty) return null;
    try {
      final cleanStr = base64Str.contains(',')
          ? base64Str.split(',').last
          : base64Str;
      return base64Decode(cleanStr.replaceAll(RegExp(r'\s+'), ''));
    } catch (e) {
      debugPrint('Error decoding base64 screenshot: $e');
      return null;
    }
  }

  void _openFullscreenViewer(BuildContext context, ScreenshotItem item) {
    final strings = context.strings;
    final bytes = _safeDecodeBase64(item.base64Image);
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) {
        final subtitle = item.isCamera
            ? '${item.facing == 'back' ? strings.cameraBackLabel : strings.cameraFrontLabel} • ${item.deviceModel ?? widget.device.name}'
            : (item.foregroundApp != null
                ? '${item.deviceModel ?? widget.device.name} • ${item.foregroundApp}'
                : (item.deviceModel ?? widget.device.name));

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.formattedDateTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const ValueKey('fullscreen_delete_button'),
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 24),
                tooltip: strings.deleteScreenshotTitle,
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF334155)),
                      ),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              strings.deleteScreenshotTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        strings.deleteScreenshotConfirm(item.formattedDateTime),
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(confirmCtx).pop(false),
                          child: Text(
                            strings.cancel,
                            style: const TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ),
                        ElevatedButton(
                          key: const ValueKey('confirm_delete_button'),
                          onPressed: () => Navigator.of(confirmCtx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: Text(strings.delete),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && ctx.mounted) {
                    Navigator.of(ctx).pop();
                    final repo = Provider.of<ScreenshotRepository>(context, listen: false);
                    final success = await repo.deleteScreenshot(widget.device.fcmToken, item.id);
                    if (!context.mounted) return;
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(strings.screenshotDeleted),
                          backgroundColor: const Color(0xFF10B981),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            repo.lastError != null && repo.lastError!.isNotEmpty
                                ? strings.errorDeletingScreenshot(repo.lastError)
                                : strings.screenshotNotDeleted,
                          ),
                          backgroundColor: const Color(0xFFEF4444),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: Center(
            child: bytes != null
                ? InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5.0,
                    clipBehavior: Clip.none,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Text(
                          strings.invalidImageFormat,
                          style: const TextStyle(color: Color(0xFFEF4444)),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      strings.imageLoadError,
                      style: const TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCloseApp(
    BuildContext context,
    ScreenshotRepository repo,
    ScreenshotItem item,
    String? effectiveIp,
  ) async {
    final strings = context.strings;
    final appName = item.foregroundApp ?? strings.unknown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.stop_circle_outlined,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.closeAppTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          strings.closeAppConfirm(appName),
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              strings.cancel,
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(strings.closeAppButton),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClosingApp = true;
    });

    try {
      final success = await repo.closeCurrentApp(
        widget.device.fcmToken,
        localIpAddress: effectiveIp,
      );

      if (!mounted || !context.mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.appClosed(appName)),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );

        // Triggers an automated screenshot refresh after 1.5 seconds so the parent sees the home screen.
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;

        await repo.captureScreenshot(
          widget.device.fcmToken,
          localIpAddress: effectiveIp,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.appCloseFailed),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClosingApp = false;
        });
      }
    }
  }

  Future<void> _confirmLockScreen(
    BuildContext context,
    ScreenshotRepository repo,
    String? effectiveIp,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.screen_lock_portrait_rounded,
                color: Color(0xFFF59E0B),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.lockTabletTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          strings.lockTabletConfirm,
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              strings.cancel,
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(strings.lockNow),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLockingScreen = true;
    });

    try {
      final success = await repo.lockScreen(
        widget.device.fcmToken,
        localIpAddress: effectiveIp,
      );

      if (!mounted || !context.mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.tabletLocked),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.tabletLockFailed),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLockingScreen = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteScreenshot(
    BuildContext context,
    ScreenshotRepository repo,
    ScreenshotItem item,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.deleteScreenshotTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          strings.deleteScreenshotConfirm(item.formattedDateTime),
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              strings.cancel,
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_delete_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(strings.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingScreenshotId = item.id;
    });

    try {
      final success = await repo.deleteScreenshot(
        widget.device.fcmToken,
        item.id,
      );

      if (!mounted || !context.mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.screenshotDeleted),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              repo.lastError != null && repo.lastError!.isNotEmpty
                  ? strings.errorDeletingScreenshot(repo.lastError)
                  : strings.screenshotNotDeleted,
            ),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingScreenshotId = null;
        });
      }
    }
  }

  Future<void> _confirmDeleteAllScreenshots(
    BuildContext context,
    ScreenshotRepository repo,
  ) async {
    final strings = context.strings;
    final count = repo.history.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_sweep_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.deleteAllScreenshotsTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          strings.deleteAllScreenshotsConfirm(count),
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              strings.cancel,
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_delete_all_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(strings.deleteAll),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeletingAll = true;
    });

    try {
      final success = await repo.deleteAllScreenshots(widget.device.fcmToken);

      if (!mounted || !context.mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.allScreenshotsDeleted),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              repo.lastError != null && repo.lastError!.isNotEmpty
                  ? strings.errorDeletingAllScreenshots(repo.lastError)
                  : strings.screenshotNotDeleted,
            ),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAll = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // Dynamically resolve effective IP from widget or VolumeRepository
    String? dynamicVolumeIp;
    try {
      dynamicVolumeIp = context.watch<VolumeRepository>().localIpAddress;
    } catch (_) {
      dynamicVolumeIp = null;
    }
    final effectiveIp = (widget.localIpAddress != null && widget.localIpAddress!.isNotEmpty)
        ? widget.localIpAddress
        : ((widget.device.localIpAddress != null && widget.device.localIpAddress!.isNotEmpty)
            ? widget.device.localIpAddress
            : dynamicVolumeIp);
    final isLanActive = effectiveIp != null && effectiveIp.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.liveScreenTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.device.name,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isLanActive
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFF6366F1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLanActive
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : const Color(0xFF6366F1).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLanActive ? Icons.wifi_rounded : Icons.cloud_outlined,
                  size: 14,
                  color: isLanActive ? const Color(0xFF10B981) : const Color(0xFF818CF8),
                ),
                const SizedBox(width: 4),
                Text(
                  isLanActive ? strings.lanDirect : strings.cloudSync,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isLanActive ? const Color(0xFF10B981) : const Color(0xFF818CF8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Consumer<ScreenshotRepository>(
        builder: (context, repo, child) {
          final isCapturing = repo.isCapturing;
          final latestScreenshot = repo.latestScreenshot;
          final history = repo.history;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Camera Facing & Flash Info Bar
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flip_camera_ios_outlined, size: 18, color: Color(0xFF818CF8)),
                      const SizedBox(width: 8),
                      Text(
                        strings.cameraLabel,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF475569)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const ValueKey('camera_facing_selector'),
                              value: _cameraFacing,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1E293B),
                              isDense: true,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'front',
                                  child: Text(strings.frontCamera),
                                ),
                                DropdownMenuItem(
                                  value: 'back',
                                  child: Text(strings.backCamera),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _cameraFacing = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.flash_off_rounded, size: 13, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Text(
                              strings.flashOff,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 1. Action Buttons Row: "Screenshot jetzt aufnehmen" & "Kamera-Foto aufnehmen"
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isCapturing
                                ? [const Color(0xFF475569), const Color(0xFF334155)]
                                : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isCapturing
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const ValueKey('capture_screenshot_button'),
                            onTap: isCapturing
                                ? null
                                : () async {
                                    setState(() => _isCapturingScreenshot = true);
                                    try {
                                      final item = await repo.captureScreenshot(
                                        widget.device.fcmToken,
                                        localIpAddress: effectiveIp,
                                      );
                                      if (!context.mounted) return;
                                      if (item != null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(strings.screenshotSuccess),
                                            backgroundColor: const Color(0xFF10B981),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      } else {
                                        final err = (repo.lastError ?? '').toLowerCase();
                                        final isPermission = repo.hasPermissionError ||
                                            ScreenshotRepository.isPermissionDenied(repo.lastError);
                                        final isAccessibilityOrTimeout = err.contains('accessibility') ||
                                            err.contains('is not connected') ||
                                            err.contains('timeout');
                                        final errorMsg = isPermission
                                            ? '${strings.firestorePermissionDenied}: ${strings.securityRulesUpdateRequired}.'
                                            : isAccessibilityOrTimeout
                                                ? strings.accessibilityServiceRequired
                                                : strings.screenshotNotReceived(repo.lastError ?? strings.unknown);

                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(errorMsg),
                                            backgroundColor: const Color(0xFFEF4444),
                                            duration: const Duration(seconds: 5),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => _isCapturingScreenshot = false);
                                    }
                                  },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isCapturingScreenshot) ...[
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      strings.running,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ] else ...[
                                    const Icon(Icons.screenshot_monitor_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        strings.captureScreenshot,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isCapturing
                                ? [const Color(0xFF475569), const Color(0xFF334155)]
                                : [const Color(0xFF0EA5E9), const Color(0xFF0284C7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isCapturing
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const ValueKey('take_camera_photo_button'),
                            onTap: isCapturing
                                ? null
                                : () async {
                                    setState(() => _isCapturingCamera = true);
                                    try {
                                      final item = await repo.takeCameraPhoto(
                                        childFcmToken: widget.device.fcmToken,
                                        localIpAddress: effectiveIp,
                                        facing: _cameraFacing,
                                        flash: false,
                                      );
                                      if (!context.mounted) return;
                                      if (item != null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(strings.cameraSuccess),
                                            backgroundColor: const Color(0xFF10B981),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      } else {
                                        final errorMsg = repo.lastError ?? strings.tabletLockFailed;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(errorMsg),
                                            backgroundColor: const Color(0xFFEF4444),
                                            duration: const Duration(seconds: 5),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => _isCapturingCamera = false);
                                    }
                                  },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isCapturingCamera) ...[
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      strings.running,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ] else ...[
                                    const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        strings.takeCameraPhoto,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 2. Action Button: "Bildschirm sperren" (Available even before screenshot)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('action_lock_screen_button'),
                      onTap: _isLockingScreen
                          ? null
                          : () => _confirmLockScreen(context, repo, effectiveIp),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isLockingScreen) ...[
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                strings.locking,
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ] else ...[
                              const Icon(
                                Icons.screen_lock_portrait_rounded,
                                color: Color(0xFFF59E0B),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                strings.lockScreen,
                                style: const TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Error Banner with dedicated clean & informative styling for permission errors
                if (repo.lastError != null) ...[
                  Builder(
                    builder: (context) {
                      final errorStr = repo.lastError!;
                      final isPermission = repo.hasPermissionError ||
                          ScreenshotRepository.isPermissionDenied(errorStr) ||
                          errorStr.toLowerCase().contains('permission-denied') ||
                          errorStr.toLowerCase().contains('berechtigung');

                      if (isPermission) {
                        return Container(
                          key: const ValueKey('screenshot_permission_error_banner'),
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF451A03).withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.admin_panel_settings_rounded,
                                      color: Color(0xFFF59E0B),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          strings.firestorePermissionDenied,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          strings.securityRulesUpdateRequired,
                                          style: const TextStyle(
                                            color: Color(0xFFFCD34D),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                strings.firestorePermissionHelp,
                                style: const TextStyle(
                                  color: Color(0xFFFEF3C7),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                                  ),
                                ),
                                child: SelectableText(
                                  strings.localFirstDiagnosisSteps,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFFFDE68A),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final isAccessibilityOrTimeout =
                          errorStr.toLowerCase().contains('accessibility') ||
                              errorStr.toLowerCase().contains('is not connected') ||
                              errorStr.toLowerCase().contains('timeout');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isAccessibilityOrTimeout
                                    ? strings.accessibilityServiceRequired
                                    : strings.screenshotNotReceived(errorStr),
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],

                // 2. Latest Screenshot or Empty State
                if (latestScreenshot == null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF334155).withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.screenshot_monitor_rounded,
                            size: 48,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          strings.noScreenshotYet,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.noScreenshotDesc,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Latest Screenshot Card
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: latestScreenshot.isCamera ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  latestScreenshot.isCamera
                                      ? (latestScreenshot.facing == 'back' ? strings.cameraBackLabel : strings.cameraFrontLabel)
                                      : strings.screenLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    latestScreenshot.formattedDateTime,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_deletingScreenshotId == latestScreenshot.id)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFEF4444),
                                    ),
                                  )
                                else
                                  IconButton(
                                    key: const ValueKey('delete_latest_screenshot_button'),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 20,
                                    ),
                                    tooltip: strings.deleteScreenshotTitle,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: _isDeletingAll || _deletingScreenshotId != null
                                        ? null
                                        : () => _confirmDeleteScreenshot(context, repo, latestScreenshot),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        if (latestScreenshot.deviceModel != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.phone_android_rounded, size: 14, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Text(
                                latestScreenshot.deviceModel!,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Image Preview Card (tap-to-expand)
                        GestureDetector(
                          onTap: () => _openFullscreenViewer(context, latestScreenshot),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 300,
                              width: double.infinity,
                              color: const Color(0xFF0F172A),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Builder(
                                    builder: (context) {
                                      final bytes = _safeDecodeBase64(latestScreenshot.base64Image);
                                      if (bytes != null) {
                                        return Image.memory(
                                          bytes,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder: (_, _, _) => const Center(
                                            child: Icon(
                                              Icons.broken_image_rounded,
                                              color: Color(0xFF64748B),
                                              size: 40,
                                            ),
                                          ),
                                        );
                                      }
                                      return const Center(
                                        child: Icon(
                                          Icons.image_not_supported_rounded,
                                          color: Color(0xFF64748B),
                                          size: 40,
                                        ),
                                      );
                                    },
                                  ),

                                  // Tap to Expand Pill
                                  Positioned(
                                    bottom: 12,
                                    right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.zoom_in_rounded, size: 16, color: Colors.white),
                                          const SizedBox(width: 6),
                                          Text(
                                            strings.zoom,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Active App Badge & Close Action Button
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.apps_rounded,
                                      size: 18,
                                      color: Color(0xFF818CF8),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          strings.activeApp(latestScreenshot.foregroundApp ?? strings.unknown),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (latestScreenshot.foregroundPackage != null &&
                                            latestScreenshot.foregroundPackage!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            latestScreenshot.foregroundPackage!,
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      key: const ValueKey('close_app_button'),
                                      onPressed: repo.isCapturing || _isClosingApp
                                          ? null
                                          : () => _confirmCloseApp(context, repo, latestScreenshot, effectiveIp),
                                      icon: _isClosingApp
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.stop_circle_outlined, size: 18),
                                      label: Text(
                                        _isClosingApp ? strings.closingApp : strings.closeAppImmediate,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFDC2626),
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: const Color(0xFF7F1D1D),
                                        disabledForegroundColor: Colors.white60,
                                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      key: const ValueKey('card_lock_screen_button'),
                                      onPressed: _isLockingScreen
                                          ? null
                                          : () => _confirmLockScreen(context, repo, effectiveIp),
                                      icon: _isLockingScreen
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.screen_lock_portrait_rounded, size: 18),
                                      label: Text(
                                        _isLockingScreen ? strings.lockingTablet : strings.lockTablet,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFD97706),
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: const Color(0xFF78350F),
                                        disabledForegroundColor: Colors.white60,
                                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. History Section
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          strings.historyCount(history.length),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('delete_all_screenshots_button'),
                          onPressed: _isDeletingAll || _deletingScreenshotId != null
                              ? null
                              : () => _confirmDeleteAllScreenshots(context, repo),
                          icon: _isDeletingAll
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFEF4444),
                                  ),
                                )
                              : const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 18),
                          label: Text(
                            _isDeletingAll ? strings.deletingAll : strings.deleteAll,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final isLatest = index == 0;
                        final bytes = _safeDecodeBase64(item.base64Image);

                        return Material(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openFullscreenViewer(context, item),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isLatest
                                      ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                                      : const Color(0xFF334155),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Thumbnail
                                  Expanded(
                                    child: Container(
                                      color: const Color(0xFF0F172A),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          if (bytes != null)
                                            Image.memory(
                                              bytes,
                                              fit: BoxFit.contain,
                                              width: double.infinity,
                                              height: double.infinity,
                                              errorBuilder: (_, _, _) => const Center(
                                                child: Icon(
                                                  Icons.broken_image_rounded,
                                                  color: Color(0xFF64748B),
                                                  size: 28,
                                                ),
                                              ),
                                            )
                                          else
                                            const Center(
                                              child: Icon(
                                                Icons.image_not_supported_rounded,
                                                color: Color(0xFF64748B),
                                                size: 28,
                                              ),
                                            ),
                                          // Badge: "📷 Front-Kamera" vs "📱 Bildschirm"
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: item.isCamera
                                                    ? const Color(0xFF0284C7).withValues(alpha: 0.9)
                                                    : const Color(0xFF1E293B).withValues(alpha: 0.85),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: item.isCamera ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                item.isCamera
                                                    ? (item.facing == 'back' ? strings.cameraBackLabel : strings.cameraFrontLabel)
                                                    : strings.screenLabel,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (isLatest)
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF6366F1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  strings.newBadge,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Metadata bar
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    color: const Color(0xFF1E293B),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (item.foregroundApp != null) ...[
                                                Text(
                                                  item.foregroundApp!,
                                                  style: const TextStyle(
                                                    color: Color(0xFF818CF8),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                              ] else if (item.isCamera) ...[
                                                Text(
                                                  item.facing == 'back' ? strings.backCameraShort : strings.frontCameraShort,
                                                  style: const TextStyle(
                                                    color: Color(0xFF38BDF8),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                              ],
                                              Text(
                                                item.formattedTime,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item.formattedDate,
                                                style: const TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_deletingScreenshotId == item.id)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFEF4444),
                                            ),
                                          )
                                        else
                                          IconButton(
                                            key: ValueKey('delete_history_screenshot_${item.id}'),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Color(0xFFEF4444),
                                              size: 18,
                                            ),
                                            tooltip: strings.deleteScreenshotTitle,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                            onPressed: _isDeletingAll || _deletingScreenshotId != null
                                                ? null
                                                : () => _confirmDeleteScreenshot(context, repo, item),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],

                const SizedBox(height: 32),
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
