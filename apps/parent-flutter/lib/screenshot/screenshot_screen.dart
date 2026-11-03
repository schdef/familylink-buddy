import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import 'screenshot_model.dart';
import 'screenshot_repository.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final repo = Provider.of<ScreenshotRepository>(context, listen: false);
        repo.subscribeToHistory(widget.device.fcmToken);
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
    final bytes = _safeDecodeBase64(item.base64Image);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (ctx) {
        final subtitle = item.foregroundApp != null
            ? '${item.deviceModel ?? widget.device.name} • ${item.foregroundApp}'
            : (item.deviceModel ?? widget.device.name);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.6),
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
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Text(
                          'Bildformat ungültig',
                          style: TextStyle(color: Color(0xFFEF4444)),
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: Text(
                      'Bilddaten konnten nicht geladen werden',
                      style: TextStyle(color: Color(0xFF94A3B8)),
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
  ) async {
    final appName = item.foregroundApp ?? 'Unbekannt';
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
                color: const Color(0xFFDC2626).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.stop_circle_outlined,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'App beenden?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          "App '$appName' beenden? Das Gerät des Kindes kehrt sofort zum Startbildschirm zurück.",
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Color(0xFF94A3B8)),
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
            child: const Text('App beenden'),
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
        localIpAddress: widget.localIpAddress,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("App '$appName' wurde beendet."),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );

        // Triggers an automated screenshot refresh after 1.5 seconds so the parent sees the home screen.
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;

        await repo.captureScreenshot(
          widget.device.fcmToken,
          localIpAddress: widget.localIpAddress,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App konnte nicht beendet werden. Ist das Gerät erreichbar?'),
            backgroundColor: Color(0xFFEF4444),
            duration: Duration(seconds: 4),
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

  @override
  Widget build(BuildContext context) {
    final isLanActive = widget.localIpAddress != null && widget.localIpAddress!.isNotEmpty;

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
            const Text(
              'Live-Bildschirm',
              style: TextStyle(
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
                  ? const Color(0xFF10B981).withOpacity(0.15)
                  : const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLanActive
                    ? const Color(0xFF10B981).withOpacity(0.4)
                    : const Color(0xFF6366F1).withOpacity(0.4),
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
                  isLanActive ? 'LAN Direct' : 'Cloud Sync',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Action Button: "Screenshot jetzt aufnehmen"
                Container(
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
                              color: const Color(0xFF6366F1).withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isCapturing
                          ? null
                          : () async {
                              final item = await repo.captureScreenshot(
                                widget.device.fcmToken,
                                localIpAddress: widget.localIpAddress,
                              );
                              if (!context.mounted) return;
                              if (item != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Screenshot erfolgreich empfangen!'),
                                    backgroundColor: Color(0xFF10B981),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                final err = (repo.lastError ?? '').toLowerCase();
                                final isAccessibilityOrTimeout = err.contains('accessibility') ||
                                    err.contains('is not connected') ||
                                    err.contains('timeout');
                                final errorMsg = isAccessibilityOrTimeout
                                    ? 'Screenshot fehlgeschlagen: Auf dem Kinder-Gerät muss der Bedienungshilfen-Dienst (Accessibility) aktiviert sein.'
                                    : 'Screenshot konnte nicht empfangen werden. Ist das Gerät online?';

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(errorMsg),
                                    backgroundColor: const Color(0xFFEF4444),
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isCapturing) ...[
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Aufnahme läuft...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ] else ...[
                              const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              const Text(
                                'Screenshot jetzt aufnehmen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
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

                if (repo.lastError != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            (repo.lastError!.toLowerCase().contains('accessibility') ||
                                    repo.lastError!.toLowerCase().contains('is not connected') ||
                                    repo.lastError!.toLowerCase().contains('timeout'))
                                ? 'Screenshot fehlgeschlagen: Auf dem Kinder-Gerät muss der Bedienungshilfen-Dienst (Accessibility) aktiviert sein.'
                                : 'Screenshot konnte nicht empfangen werden: ${repo.lastError}',
                            style: const TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                            color: const Color(0xFF334155).withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.screenshot_monitor_rounded,
                            size: 48,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Noch kein Screenshot vorhanden',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tippe auf den Button oben, um den aktuellen Bildschirm des Kindes in Echtzeit abzurufen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
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
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Aktueller Bildschirm',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
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
                                          errorBuilder: (_, __, ___) => const Center(
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
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.zoom_in_rounded, size: 16, color: Colors.white),
                                          SizedBox(width: 6),
                                          Text(
                                            'Vergrößern',
                                            style: TextStyle(
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
                                      color: const Color(0xFF6366F1).withOpacity(0.15),
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
                                          'Aktive App: ${latestScreenshot.foregroundApp ?? 'Unbekannt'}',
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
                              ElevatedButton.icon(
                                onPressed: repo.isCapturing || _isClosingApp
                                    ? null
                                    : () => _confirmCloseApp(context, repo, latestScreenshot),
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
                                label: Text(_isClosingApp ? 'Wird beendet...' : 'App sofort beenden'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(0xFF7F1D1D),
                                  disabledForegroundColor: Colors.white60,
                                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. History Section
                  if (history.length > 1) ...[
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Verlauf (${history.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Alle Aufnahmen',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
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
                        childAspectRatio: 0.72,
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
                                      ? const Color(0xFF6366F1).withOpacity(0.5)
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
                                              errorBuilder: (_, __, ___) => const Center(
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
                                                child: const Text(
                                                  'NEU',
                                                  style: TextStyle(
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
          );
        },
      ),
    );
  }
}
