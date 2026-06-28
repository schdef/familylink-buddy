import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
    if (childFcmToken == 'emulator' || childFcmToken.length < 50) {
      try {
        final url = Uri.parse('http://10.0.2.2:8080/set_volume?stream=$stream&level=$level');
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

    final requestId = const Uuid().v4();
    final payload = {
      'to': childFcmToken,
      'data': {
        'type': 'SET_VOLUME',
        'stream': stream,
        'level': level.toString(),
        'parentToken': _parentFcmToken ?? '',
        'requestId': requestId,
      },
    };

    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_fcmServerKey',
        },
        body: jsonEncode(payload),
      );
      debugPrint('FCM send status: ${response.statusCode} ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('FCM send error: $e');
      return false;
    }
  }

  /// Request a volume report from the child device (or local HTTP in dev mode)
  Future<void> requestVolumeReport(String childFcmToken) async {
    if (childFcmToken == 'emulator' || childFcmToken.length < 50) {
      try {
        final url = Uri.parse('http://10.0.2.2:8080/volume_report');
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

    final payload = {
      'to': childFcmToken,
      'data': {
        'type': 'GET_VOLUME',
        'parentToken': _parentFcmToken ?? '',
      },
    };
    try {
      await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_fcmServerKey',
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('FCM request error: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Background FCM handler — must be a top-level function
  debugPrint('Background FCM message: ${message.data}');
}
