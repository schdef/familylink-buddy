import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  String? _localIpAddress;

  VolumeState get volumeState => _volumeState;
  bool get isConnected => _isConnected;
  DateTime? get lastSeen => _lastSeen;
  String? get localIpAddress => _localIpAddress;

  @visibleForTesting
  set localIpAddress(String? ip) => _localIpAddress = ip;

  StreamSubscription<DocumentSnapshot>? _subscription;

  void subscribeToDevice(String childFcmToken) {
    _subscription?.cancel();
    if (childFcmToken.isEmpty || childFcmToken == 'emulator') return;

    _subscription = FirebaseFirestore.instance
        .collection('pairings')
        .doc(childFcmToken)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          _localIpAddress = data['localIpAddress'] as String?;

          final dbLastSeen = data['lastSeen'] as Timestamp?;
          if (dbLastSeen != null) {
            _lastSeen = dbLastSeen.toDate();
            _isConnected = true;
          }

          final report = data['volumeReport'] as Map<dynamic, dynamic>?;
          if (report != null) {
            final int mediaVol = (report['mediaVolume'] as num?)?.toInt() ?? -1;
            final int ringtoneVol = (report['ringtoneVolume'] as num?)?.toInt() ?? -1;
            final int alarmVol = (report['alarmVolume'] as num?)?.toInt() ?? -1;
            _volumeState = VolumeState(
              mediaVolume: mediaVol,
              ringtoneVolume: ringtoneVol,
              alarmVolume: alarmVol,
              maxMediaVolume: (report['maxMediaVolume'] as num?)?.toInt() ?? 15,
              maxRingtoneVolume: (report['maxRingtoneVolume'] as num?)?.toInt() ?? 15,
              maxAlarmVolume: (report['maxAlarmVolume'] as num?)?.toInt() ?? 15,
              isMuted: mediaVol == 0 && ringtoneVol == 0,
              timestamp: DateTime.now(),
            );
            _isConnected = true;
            if (dbLastSeen == null) {
              _lastSeen = DateTime.now();
            }
          }
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // FCM server key (from Firebase Console → Project Settings → Cloud Messaging)
  // In production this should be fetched securely from a backend, not hardcoded.
  static const _fcmServerKey = 'YOUR_FCM_SERVER_KEY';

  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission for notifications
      await messaging.requestPermission();

      // Store our own FCM token (parent token for child to reply to)
      _parentFcmToken = await messaging.getToken();
      debugPrint('Parent FCM token: $_parentFcmToken');

      // Listen for incoming volume reports from child
      FirebaseMessaging.onMessage.listen(_handleIncomingMessage);
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    } catch (e) {
      debugPrint('FCM initialization failed (falling back to Firestore direct sync): $e');
    }
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

  void _updateVolumeStateLocally(String stream, int level) {
    _volumeState = VolumeState(
      mediaVolume: stream == 'MEDIA' || stream == 'ALL' ? level : _volumeState.mediaVolume,
      ringtoneVolume: stream == 'RINGTONE' || stream == 'ALL' ? level : _volumeState.ringtoneVolume,
      alarmVolume: stream == 'ALARM' || stream == 'ALL' ? level : _volumeState.alarmVolume,
      maxMediaVolume: _volumeState.maxMediaVolume,
      maxRingtoneVolume: _volumeState.maxRingtoneVolume,
      maxAlarmVolume: _volumeState.maxAlarmVolume,
      isMuted: level == 0 && (stream == 'ALL' || (stream == 'MEDIA' && _volumeState.ringtoneVolume == 0)),
      timestamp: DateTime.now(),
    );
    _isConnected = true;
    _lastSeen = DateTime.now();
    notifyListeners();
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
          _updateVolumeStateLocally(stream, level);
          return true;
        }
      } catch (e) {
        debugPrint('Local HTTP volume change failed: $e');
      }
      return false;
    }

    // Try Direct local network REST API first
    if (_localIpAddress != null && _localIpAddress!.isNotEmpty) {
      try {
        final url = Uri.parse('http://$_localIpAddress:8085/set_volume?stream=$stream&level=$level');
        debugPrint('Attempting direct local network volume change to: $url');
        final response = await http.post(url).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          debugPrint('Direct local network volume change succeeded!');
          _updateVolumeStateLocally(stream, level);
          return true;
        }
      } catch (e) {
        debugPrint('Direct local network volume change failed: $e. Falling back to Firestore.');
      }
    }

    // Fallback: Firestore write
    try {
      await FirebaseFirestore.instance.collection('pairings').doc(childFcmToken).update({
        'volumeCommand': {
          'stream': stream,
          'level': level,
          'timestamp': FieldValue.serverTimestamp()
        }
      });
      return true;
    } catch (e) {
      debugPrint('Firestore direct setVolume failed: $e');
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

    // Try Direct local network REST API first
    if (_localIpAddress != null && _localIpAddress!.isNotEmpty) {
      try {
        final url = Uri.parse('http://$_localIpAddress:8085/volume_report');
        debugPrint('Attempting direct local network volume report request to: $url');
        final response = await http.get(url).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          debugPrint('Direct local network volume report succeeded!');
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _volumeState = VolumeState.fromJson(data);
          _isConnected = true;
          _lastSeen = DateTime.now();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('Direct local network volume report failed: $e. Falling back to Firestore.');
      }
    }

    // Fallback: Firestore write
    try {
      await FirebaseFirestore.instance.collection('pairings').doc(childFcmToken).update({
        'volumeCommand': {
          'stream': 'GET_VOLUME',
          'level': 0,
          'timestamp': FieldValue.serverTimestamp()
        }
      });
    } catch (e) {
      debugPrint('Firestore direct requestVolumeReport failed: $e');
    }
  }

  static String getLastSeenText(DateTime? lastSeen, {DateTime? now}) {
    if (lastSeen == null) return 'Keine Verbindungshistorie';
    final referenceTime = now ?? DateTime.now();
    final diff = referenceTime.difference(lastSeen);
    if (diff.inSeconds < 10) {
      return 'Gerade eben aktiv';
    } else if (diff.inSeconds < 60) {
      return 'Vor ${diff.inSeconds} Sek. aktiv';
    } else if (diff.inMinutes < 60) {
      return 'Vor ${diff.inMinutes} Min. aktiv';
    } else {
      final hours = diff.inHours;
      if (hours < 24) {
        return 'Vor $hours Std. aktiv';
      } else {
        return 'Vor ${diff.inDays} Tagen aktiv';
      }
    }
  }
}

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Background FCM handler — must be a top-level function
  debugPrint('Background FCM message: ${message.data}');
}
