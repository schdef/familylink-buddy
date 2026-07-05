import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UpdaterService {
  static const _platform = MethodChannel('com.familylink.buddy.parent/updater');

  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      // 1. Get local version code
      final int localVersionCode = await _platform.invokeMethod('getAppVersionCode');

      // 2. Fetch remote metadata from Firestore
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('app_metadata')
          .doc('releases')
          .get();

      if (!doc.exists) return;

      final Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
      if (data == null || !data.containsKey('parent')) return;

      final Map<String, dynamic> parentData = Map<String, dynamic>.from(data['parent']);
      final int remoteVersionCode = parentData['versionCode'] ?? 0;
      final String remoteVersionName = parentData['versionName'] ?? '1.0.0';
      final String downloadUrl = parentData['downloadUrl'] ?? '';

      if (remoteVersionCode > localVersionCode && downloadUrl.isNotEmpty) {
        // Show update prompt dialog
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return _UpdateDialog(
                downloadUrl: downloadUrl,
                versionName: remoteVersionName,
              );
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }
}

class _UpdateDialog extends StatefulWidget {
  final String downloadUrl;
  final String versionName;

  const _UpdateDialog({
    required this.downloadUrl,
    required this.versionName,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = -1.0; // -1.0 means download not started
  bool _isDownloading = false;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('HTTP Status Code ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final List<int> bytes = [];

      final Directory tempDir = await getTemporaryDirectory();
      final File apkFile = File('${tempDir.path}/update.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final IOSink sink = apkFile.openWrite();

      int bytesRead = 0;
      await response.stream.listen(
        (List<int> chunk) {
          sink.add(chunk);
          bytesRead += chunk.length;
          if (contentLength > 0) {
            setState(() {
              _progress = bytesRead / contentLength;
            });
          }
        },
        onDone: () async {
          await sink.close();
          client.close();

          // Trigger installer
          try {
            await UpdaterService._platform.invokeMethod('installApk', {
              'filePath': apkFile.path,
            });
          } catch (installError) {
            debugPrint('Install invocation error: $installError');
          }
        },
        onError: (err) {
          sink.close();
          client.close();
          setState(() {
            _progress = -1.0;
            _isDownloading = false;
          });
        },
        cancelOnError: true,
      ).asFuture();
    } catch (e) {
      debugPrint('Download update error: $e');
      setState(() {
        _progress = -1.0;
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F2833),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Update Verfügbar 🚀',
        style: TextStyle(
          color: Color(0xFF66FCF1),
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Eine neue Version von FamilyLink Buddy Parent (${widget.versionName}) ist verfügbar. Bitte installieren Sie das Update, um fortzufahren.',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (_progress >= 0.0) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white10,
              color: const Color(0xFF66FCF1),
            ),
            const SizedBox(height: 8),
            Text(
              'Herunterladen: ${(_progress * 100).toInt()}%',
              style: const TextStyle(color: Color(0xFF45A29E), fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: _startDownload,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF66FCF1),
            ),
            child: const Text('Download & Installieren'),
          ),
      ],
    );
  }
}
