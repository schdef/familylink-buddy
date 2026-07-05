import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final _uuid = const Uuid();

  bool _isConnecting = false;
  bool _isStreaming = false;
  String? _activeSessionId;
  StreamSubscription<DocumentSnapshot>? _signalingSubscription;

  bool get isConnecting => _isConnecting;
  bool get isStreaming => _isStreaming;
  String? get activeSessionId => _activeSessionId;

  // Mock settings values
  bool childCanInitiate = true;
  bool autoPlayVoice = true;

  // Callbacks for WebRTC signaling state mapping
  Function(String offer)? onOfferReceived;
  Function(String answer)? onAnswerReceived;
  Function(String candidate, String sdpMid, int sdpMLineIndex)? onIceCandidateReceived;

  /// Starts a Walkie-Talkie session.
  /// Writes Session offer directly to signaling collection and triggers activeCommsSessionId update.
  Future<bool> startWalkieTalkieSession({
    required String childToken,
    required String localSdpOffer,
    bool isEmulator = false,
  }) async {
    _isConnecting = true;
    notifyListeners();

    final sessionId = 'comms_${_uuid.v4()}';
    _activeSessionId = sessionId;

    if (isEmulator) {
      // Local dev emulation route: Hit the local Android developer server directly
      try {
        final url = Uri.parse('http://10.0.2.2:8085/comms/walkie-talkie/simulate_receive');
        final response = await http.post(url);
        if (response.statusCode == 200) {
          _isConnecting = false;
          _isStreaming = true;
          notifyListeners();
          return true;
        }
      } catch (e) {
        debugPrint('Comms local simulator launch failed: $e');
      }
      _isConnecting = false;
      notifyListeners();
      return false;
    }

    try {
      final docRef = _firestore
          .collection('pairings')
          .doc(childToken)
          .collection('comms')
          .doc('signaling')
          .collection('sessions')
          .doc(sessionId);

      // 1. Write the initial SDP Offer session document
      await docRef.set({
        'type': 'OFFER',
        'sdp': localSdpOffer,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Trigger the active session listener on child
      await _firestore.collection('pairings').doc(childToken).update({
        'activeCommsSessionId': sessionId,
        'activeCommsSessionTimestamp': FieldValue.serverTimestamp(),
      });

      // 3. Listen to remote SDP response / Answer from child
      _signalingSubscription = docRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            final type = data['type'] as String?;
            if (type == 'ANSWER') {
              final answerSdp = data['sdp'] as String?;
              if (answerSdp != null && onAnswerReceived != null) {
                _isConnecting = false;
                _isStreaming = true;
                notifyListeners();
                onAnswerReceived!(answerSdp);
              }
            } else if (type == 'ICE_CANDIDATE') {
              final candidate = data['candidate'] as String?;
              final sdpMid = data['sdpMid'] as String?;
              final sdpMLineIndex = data['sdpMLineIndex'] as int?;
              if (candidate != null && sdpMid != null && sdpMLineIndex != null && onIceCandidateReceived != null) {
                onIceCandidateReceived!(candidate, sdpMid, sdpMLineIndex);
              }
            }
          }
        }
      });

      return true;
    } catch (e) {
      debugPrint('Firestore comms startWalkieTalkieSession error: $e');
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  /// Sends a local ICE Candidate to the child device
  Future<void> sendIceCandidate({
    required String childToken,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;

    try {
      await _firestore
          .collection('pairings')
          .doc(childToken)
          .collection('comms')
          .doc('signaling')
          .collection('sessions')
          .doc(sessionId)
          .update({
            'type': 'ICE_CANDIDATE',
            'candidate': candidate,
            'sdpMid': sdpMid,
            'sdpMLineIndex': sdpMLineIndex,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Firestore comms sendIceCandidate error: $e');
    }
  }

  /// Tears down the active signaling session
  Future<void> closeSession({
    required String childToken,
    bool isEmulator = false,
  }) async {
    _signalingSubscription?.cancel();
    _signalingSubscription = null;

    final sessionId = _activeSessionId;
    _activeSessionId = null;
    _isConnecting = false;
    _isStreaming = false;
    notifyListeners();

    if (isEmulator) return;
    if (sessionId == null) return;

    try {
      // Notify client session is closing
      await _firestore
          .collection('pairings')
          .doc(childToken)
          .collection('comms')
          .doc('signaling')
          .collection('sessions')
          .doc(sessionId)
          .set({
            'type': 'CLOSE',
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Firestore comms closeSession error: $e');
    }
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

    try {
      await _firestore
          .collection('pairings')
          .doc(childToken)
          .collection('comms')
          .doc('settings')
          .set({
            'childCanInitiate': childCanInitiateVal,
            'autoPlayVoice': autoPlayVoiceVal,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Firestore comms settings write failed: $e');
    }
  }

  bool _childIsSpeaking = false;
  bool get childIsSpeaking => _childIsSpeaking;
  
  String? _missedCallNotification;
  String? get missedCallNotification => _missedCallNotification;

  StreamSubscription<DocumentSnapshot>? _childSpeakingSubscription;

  void listenToChildSpeaking(String childToken) {
    _childSpeakingSubscription?.cancel();
    if (childToken.isEmpty) return;

    _childSpeakingSubscription = _firestore
        .collection('pairings')
        .doc(childToken)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          final childSpeakingVal = data['childIsSpeaking'] as bool? ?? false;
          
          if (childSpeakingVal && !_childIsSpeaking) {
            // Child started speaking
            final lifecycle = WidgetsBinding.instance.lifecycleState;
            final isAppActive = lifecycle == AppLifecycleState.resumed;

            if (isAppActive) {
              // Phone is active: Play it directly (update state)
              _isStreaming = true;
              _missedCallNotification = null;
              debugPrint('[AUDIO PLAY] Walkie-Talkie stream active from child (Phone Active)');
            } else {
              // Phone is deactivated: Only trigger a notification!
              _missedCallNotification = 'Verpasste Walkie-Talkie Nachricht um ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} Uhr';
              debugPrint('[NOTIFICATION] Eingehende Sprachnachricht von Kind (Telefon Deaktiviert)');
            }
            notifyListeners();
          } else if (!childSpeakingVal && _childIsSpeaking) {
            // Child stopped speaking
            _isStreaming = false;
            notifyListeners();
          }
          _childIsSpeaking = childSpeakingVal;
        }
      }
    });
  }

  void clearMissedNotification() {
    _missedCallNotification = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _signalingSubscription?.cancel();
    _childSpeakingSubscription?.cancel();
    super.dispose();
  }
}
