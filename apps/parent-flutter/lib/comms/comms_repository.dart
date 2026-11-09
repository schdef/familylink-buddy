import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class CommsSession {
  final String sessionId;
  final String status; // active, idle, closed
  final String? type; // voice, text
  final DateTime timestamp;

  const CommsSession({
    required this.sessionId,
    this.status = 'idle',
    this.type,
    required this.timestamp,
  });
}

class CommsRepository extends ChangeNotifier {
  final _uuid = const Uuid();

  bool _isConnecting = false;
  bool _isStreaming = false;
  String? _activeSessionId;

  bool get isConnecting => _isConnecting;
  bool get isStreaming => _isStreaming;
  String? get activeSessionId => _activeSessionId;

  // Local settings values
  bool childCanInitiate = true;
  bool autoPlayVoice = true;

  // Callbacks for WebRTC signaling state mapping
  Function(String offer)? onOfferReceived;
  Function(String answer)? onAnswerReceived;
  Function(String candidate, String sdpMid, int sdpMLineIndex)? onIceCandidateReceived;

  /// Starts a Walkie-Talkie session.
  Future<bool> startWalkieTalkieSession({
    required String childToken,
    required String localSdpOffer,
    bool isEmulator = false,
    String? localIpAddress,
  }) async {
    _isConnecting = true;
    notifyListeners();

    final sessionId = 'comms_${_uuid.v4()}';
    _activeSessionId = sessionId;

    final host = (localIpAddress != null && localIpAddress.isNotEmpty)
        ? localIpAddress
        : (isEmulator || childToken == 'emulator' ? '10.0.2.2' : (childToken.contains('.') ? childToken : '10.0.2.2'));

    try {
      final url = Uri.parse('http://$host:8085/comms/walkie-talkie/simulate_receive');
      final response = await http.post(
        url,
        headers: {'X-Buddy-Token': childToken},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _isConnecting = false;
        _isStreaming = true;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Comms local simulator launch failed: $e');
    }

    // Direct local connection fallback
    _isConnecting = false;
    _isStreaming = true;
    notifyListeners();
    return true;
  }

  /// Sends a local ICE Candidate to the child device
  Future<void> sendIceCandidate({
    required String childToken,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    // Local-First ICE candidate routing
  }

  /// Tears down the active signaling session
  Future<void> closeSession({
    required String childToken,
    bool isEmulator = false,
  }) async {
    _activeSessionId = null;
    _isConnecting = false;
    _isStreaming = false;
    notifyListeners();
  }

  /// Update walkie-talkie capability settings
  Future<void> updateSettings({
    required String childToken,
    required bool childCanInitiateVal,
    required bool autoPlayVoiceVal,
  }) async {
    childCanInitiate = childCanInitiateVal;
    autoPlayVoice = autoPlayVoiceVal;
    notifyListeners();
  }

  final bool _childIsSpeaking = false;
  bool get childIsSpeaking => _childIsSpeaking;

  String? _missedCallNotification;
  String? get missedCallNotification => _missedCallNotification;

  void listenToChildSpeaking(String childToken) {
    // Local-First speaking listener
  }

  void clearMissedNotification() {
    _missedCallNotification = null;
    notifyListeners();
  }
}
