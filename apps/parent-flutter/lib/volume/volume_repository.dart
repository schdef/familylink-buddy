import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class VolumeState {
  final int mediaVolume;
  final int ringtoneVolume;
  final int alarmVolume;
  final int maxMediaVolume;
  final int maxRingtoneVolume;
  final int maxAlarmVolume;
  final bool isMuted;
  final DateTime? timestamp;

  const VolumeState({
    this.mediaVolume = -1,
    this.ringtoneVolume = -1,
    this.alarmVolume = -1,
    this.maxMediaVolume = 15,
    this.maxRingtoneVolume = 15,
    this.maxAlarmVolume = 15,
    this.isMuted = false,
    this.timestamp,
  });

  factory VolumeState.fromJson(Map<String, dynamic> json) {
    return VolumeState(
      mediaVolume: json['mediaVolume'] as int? ?? -1,
      ringtoneVolume: json['ringtoneVolume'] as int? ?? -1,
      alarmVolume: json['alarmVolume'] as int? ?? -1,
      maxMediaVolume: json['maxMediaVolume'] as int? ?? 15,
      maxRingtoneVolume: json['maxRingtoneVolume'] as int? ?? 15,
      maxAlarmVolume: json['maxAlarmVolume'] as int? ?? 15,
      isMuted: json['isMuted'] as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : null,
    );
  }

  bool get isKnown => mediaVolume >= 0;
}

class VolumeRepository extends ChangeNotifier {
  VolumeState _volumeState = const VolumeState();
  bool _isConnected = false;
  DateTime? _lastSeen;
  String? _parentFcmToken;

  VolumeState get volumeState => _volumeState;
  bool get isConnected => _isConnected;
  DateTime? get lastSeen => _lastSeen;

  // FCM server key (from Firebase Console → Project Settings → Cloud Messaging)
  // In production this should be fetched securely from a backend, not hardcoded.
  static const _fcmServerKey = 'YOUR_FCM_SERVER_KEY';

  Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission for notifications
    await messaging.requestPermission();

    // Store our own FCM token (parent token for child to reply to)
    _parentFcmToken = await messaging.getToken();
    debugPrint('Parent FCM token: $_parentFcmToken');

    // Listen for incoming volume reports from child
    FirebaseMessaging.onMessage.listen(_handleIncomingMessage);
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
  }

  void _handleIncomingMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'VOLUME_REPORT') {
      _volumeState = VolumeState.fromJson(data.map(
        (k, v) => MapEntry(k, int.tryParse(v.toString()) ?? v),
      ));
      _isConnected = true;
      _lastSeen = DateTime.now();
      notifyListeners();
    }
  }

  /// Send a SET_VOLUME command to the child device via FCM (or local HTTP in dev mode)
  Future<bool> setVolume({
    required String childFcmToken,
    required String stream, // MEDIA | RINGTONE | ALARM | ALL
    required int level,
  }) async {
    if (childFcmToken == 'emulator') {
      try {
        final url = Uri.parse('http://10.0.2.2:8085/set_volume?stream=$stream&level=$level');
        final response = await http.post(url);
        if (response.statusCode == 200) {
          _volumeState = VolumeState(
            mediaVolume: stream == 'MEDIA' || stream == 'ALL' ? level : _volumeState.mediaVolume,
            ringtoneVolume: stream == 'RINGTONE' || stream == 'ALL' ? level : _volumeState.ringtoneVolume,
            alarmVolume: stream == 'ALARM' || stream == 'ALL' ? level : _volumeState.alarmVolume,
            maxMediaVolume: _volumeState.maxMediaVolume,
            maxRingtoneVolume: _volumeState.maxRingtoneVolume,
            maxAlarmVolume: _volumeState.maxAlarmVolume,
            isMuted: level == 0 && stream == 'ALL',
            timestamp: DateTime.now(),
          );
          _isConnected = true;
          _lastSeen = DateTime.now();
          notifyListeners();
          return true;
        }
      } catch (e) {
        debugPrint('Local HTTP volume change failed: $e');
      }
      return false;
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('setVolume')
          .call({
            'childToken': childFcmToken,
            'stream': stream,
            'level': level
          });
      final resData = result.data as Map<dynamic, dynamic>;
      return resData['status'] == 'success';
    } catch (e) {
      debugPrint('Cloud Function setVolume failed: $e');
      return false;
    }
  }

  /// Request a volume report from the child device (or local HTTP in dev mode)
  Future<void> requestVolumeReport(String childFcmToken) async {
    if (childFcmToken == 'emulator') {
      try {
        final url = Uri.parse('http://10.0.2.2:8085/volume_report');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _volumeState = VolumeState.fromJson(data);
          _isConnected = true;
          _lastSeen = DateTime.now();
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Local HTTP volume report failed: $e');
      }
      return;
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('forceSync')
          .call({'childToken': childFcmToken});
    } catch (e) {
      debugPrint('Cloud Function forceSync failed: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Background FCM handler — must be a top-level function
  debugPrint('Background FCM message: ${message.data}');
}
