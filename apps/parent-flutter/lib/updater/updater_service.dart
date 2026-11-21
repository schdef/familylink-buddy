import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'update_dialog.dart';

class ReleaseInfo {
  final String tagName;
  final String releaseNotes;
  final String? parentApkUrl;
  final String? childApkUrl;
  final String htmlUrl;

  const ReleaseInfo({
    required this.tagName,
    required this.releaseNotes,
    this.parentApkUrl,
    this.childApkUrl,
    required this.htmlUrl,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? 'v1.0.0';
    final releaseNotes = json['body'] as String? ?? '';
    final htmlUrl = json['html_url'] as String? ?? 'https://github.com/schdef/familylink-buddy/releases';

    String? parentApk;
    String? childApk;

    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          final downloadUrl = asset['browser_download_url'] as String?;
          if (name == 'parent-app-release.apk' || (name.contains('parent') && name.endsWith('.apk'))) {
            parentApk = downloadUrl;
          } else if (name == 'child-app-release.apk' || (name.contains('child') && name.endsWith('.apk'))) {
            childApk = downloadUrl;
          }
        }
      }
    }

    // Fallback URL if assets not attached
    parentApk ??= 'https://raw.githubusercontent.com/schdef/familylink-buddy/main/build/parent-app-release.apk';
    childApk ??= 'https://raw.githubusercontent.com/schdef/familylink-buddy/main/build/child-app-release.apk';

    return ReleaseInfo(
      tagName: tagName,
      releaseNotes: releaseNotes,
      parentApkUrl: parentApk,
      childApkUrl: childApk,
      htmlUrl: htmlUrl,
    );
  }
}

class UpdaterService {
  static const MethodChannel _platform = MethodChannel('com.familylink.buddy.parent/updater');
  static const String currentVersion = '1.1.2';

  static MethodChannel get platformChannel => _platform;

  /// Compares semantic versions (e.g. 'v1.1.3' vs '1.1.2').
  /// Returns true if [latestTag] is higher than [current].
  static bool isNewerVersion(String latestTag, String current) {
    try {
      final cleanLatest = latestTag.replaceAll(RegExp(r'^[vV]'), '').split('+').first;
      final cleanCurrent = current.replaceAll(RegExp(r'^[vV]'), '').split('+').first;

      final latestParts = cleanLatest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fetches latest release metadata from GitHub repository releases endpoint.
  static Future<ReleaseInfo?> fetchLatestRelease({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final url = Uri.parse('https://api.github.com/repos/schdef/familylink-buddy/releases/latest');
    try {
      final response = await httpClient.get(
        url,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
        return ReleaseInfo.fromJson(jsonMap);
      }
      return null;
    } catch (e) {
      debugPrint('UpdaterService.fetchLatestRelease error: $e');
      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Downloads parent APK to temporary storage and invokes native package installer.
  static Future<bool> downloadAndInstallParentApk({
    required String apkUrl,
    required Function(double progress) onProgress,
    http.Client? client,
  }) async {
    if (kIsWeb) {
      return false;
    }
    final httpClient = client ?? http.Client();
    try {
      final file = await _downloadFile(
        url: apkUrl,
        fileName: 'parent-update.apk',
        onProgress: onProgress,
        client: httpClient,
      );
      if (file == null) return false;

      final bool? result = await _platform.invokeMethod<bool>('installApk', {'filePath': file.path});
      return result ?? false;
    } catch (e) {
      debugPrint('UpdaterService.downloadAndInstallParentApk error: $e');
      return false;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Downloads child APK to temporary storage for subsequent P2P push to child tablet.
  static Future<String?> downloadChildApk({
    required String apkUrl,
    required Function(double progress) onProgress,
    http.Client? client,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final httpClient = client ?? http.Client();
    try {
      final file = await _downloadFile(
        url: apkUrl,
        fileName: 'child-update.apk',
        onProgress: onProgress,
        client: httpClient,
      );
      return file?.path;
    } catch (e) {
      debugPrint('UpdaterService.downloadChildApk error: $e');
      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  static Future<File?> _downloadFile({
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
    required http.Client client,
  }) async {
    final uri = Uri.parse(url);
    final request = http.Request('GET', uri);
    final response = await client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Failed to download update: HTTP ${response.statusCode}', uri: uri);
    }

    final totalBytes = response.contentLength ?? -1;
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$fileName');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final sink = file.openWrite();
    int receivedBytes = 0;
    onProgress(0.0);

    final completer = Completer<void>();

    response.stream.listen(
      (chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(progress);
        }
      },
      onDone: () async {
        await sink.flush();
        await sink.close();
        onProgress(1.0);
        completer.complete();
      },
      onError: (err, stackTrace) async {
        await sink.close();
        completer.completeError(err, stackTrace);
      },
      cancelOnError: true,
    );

    await completer.future;
    return file;
  }

  /// Displays the interactive update dialog to check, download, and install updates.
  static Future<void> showUpdateDialog(
    BuildContext context, {
    String? childIp,
    http.Client? client,
    VoidCallback? onOpenManualP2p,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => UpdateDialog(
        childIp: childIp,
        client: client,
        onOpenManualP2p: onOpenManualP2p,
      ),
    );
  }

  /// Silent check or manual trigger.
  static Future<void> checkForUpdates(BuildContext context) async {
    // Silent check on launch, no intrusive popups unless user manually requests updates.
  }

  static Future<int> getLocalVersionCode() async {
    try {
      final int localVersionCode = await _platform.invokeMethod('getAppVersionCode');
      return localVersionCode;
    } catch (_) {
      return 1;
    }
  }
}
