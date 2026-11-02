import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class P2PUpdaterService {
  final http.Client? _client;
  static const MethodChannel _channel = MethodChannel('com.familylink.buddy.parent/updater');

  P2PUpdaterService({http.Client? client}) : _client = client;

  /// Invokes the native file picker via Storage Access Framework (SAF)
  /// allowing selecting an APK from local device storage or Google Drive.
  ///
  /// Returns a Map with keys:
  /// - 'path': String (absolute path to cached APK file)
  /// - 'name': String (original display name)
  /// - 'size': int (file size in bytes)
  /// or null if the user cancelled the picker.
  Future<Map<String, dynamic>?> pickApkFile() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickApkFile');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      debugPrint('pickApkFile error: ${e.message}');
      rethrow;
    }
  }

  /// Streams the APK file bytes via HTTP POST to http://$childLocalIp:8085/upload_update
  /// with live progress reporting (0.0 to 1.0).
  Future<bool> pushUpdateToChild({
    required String childLocalIp,
    required String apkFilePath,
    required Function(double progress) onProgress,
  }) async {
    final file = File(apkFilePath);
    if (!await file.exists()) {
      throw FileSystemException('APK-Datei nicht gefunden', apkFilePath);
    }

    final totalBytes = await file.length();
    if (totalBytes <= 0) {
      throw Exception('APK-Datei ist leer');
    }

    final url = Uri.parse('http://$childLocalIp:8085/upload_update');
    final client = _client ?? http.Client();

    try {
      final request = http.StreamedRequest('POST', url);
      request.contentLength = totalBytes;
      request.headers['Content-Type'] = 'application/vnd.android.package-archive';
      request.headers['X-File-Name'] = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'update.apk';

      int bytesSent = 0;
      onProgress(0.0);

      final fileStream = file.openRead();
      fileStream.listen(
        (chunk) {
          bytesSent += chunk.length;
          request.sink.add(chunk);
          final progress = (bytesSent / totalBytes).clamp(0.0, 1.0);
          onProgress(progress);
        },
        onDone: () {
          request.sink.close();
        },
        onError: (error, stackTrace) {
          request.sink.addError(error, stackTrace);
        },
        cancelOnError: true,
      );

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        onProgress(1.0);
        return true;
      } else {
        throw HttpException(
          'Upload fehlgeschlagen: Status ${response.statusCode} - ${response.body}',
          uri: url,
        );
      }
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}
