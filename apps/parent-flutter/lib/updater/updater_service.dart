import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UpdaterService {
  static const _platform = MethodChannel('com.familylink.buddy.parent/updater');

  static Future<void> checkForUpdates(BuildContext context) async {
    // Local-First: Cloud Firestore update checks disabled.
    // P2P APK updates can be transferred directly over LAN.
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
