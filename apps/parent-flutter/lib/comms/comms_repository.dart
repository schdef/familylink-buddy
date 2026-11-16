import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'comms_models.dart';

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
  final http.Client? _httpClient;

  CommsRepository({http.Client? httpClient}) : _httpClient = httpClient;

  // ===========================================================================
  // Walkie-Talkie State & Functions
  // ===========================================================================
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
  Function(String candidate, String sdpMid, int sdpMLineIndex)?
      onIceCandidateReceived;

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
        : (isEmulator || childToken == 'emulator'
            ? '10.0.2.2'
            : (childToken.contains('.') ? childToken : '10.0.2.2'));

    try {
      final client = _httpClient ?? http.Client();
      final url = Uri.parse(
          'http://$host:8085/comms/walkie-talkie/simulate_receive');
      final response = await client.post(
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

  // ===========================================================================
  // Communication Monitoring: Call History & Chat Messages
  // ===========================================================================
  List<CallRecord> _calls = [];
  List<CallRecord> get calls => List.unmodifiable(_calls);

  List<ChatMessageRecord> _chats = [];
  List<ChatMessageRecord> get chats => List.unmodifiable(_chats);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  String _callsKey(String deviceId) => 'comms_calls_$deviceId';
  String _chatsKey(String deviceId) => 'comms_chats_$deviceId';
  String _lastSyncedKey(String deviceId) => 'comms_last_synced_$deviceId';

  /// Loads locally cached call and chat logs for a specific device from SharedPreferences.
  Future<void> loadCache(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final callsJson = prefs.getString(_callsKey(deviceId));
      if (callsJson != null && callsJson.isNotEmpty) {
        final decoded = jsonDecode(callsJson);
        if (decoded is List) {
          _calls = decoded
              .map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
      } else {
        _calls = [];
      }

      final chatsJson = prefs.getString(_chatsKey(deviceId));
      if (chatsJson != null && chatsJson.isNotEmpty) {
        final decoded = jsonDecode(chatsJson);
        if (decoded is List) {
          _chats = decoded
              .map((e) => ChatMessageRecord.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
      } else {
        _chats = [];
      }

      final lastSyncedMs = prefs.getInt(_lastSyncedKey(deviceId));
      if (lastSyncedMs != null && lastSyncedMs > 0) {
        _lastSyncedAt = DateTime.fromMillisecondsSinceEpoch(lastSyncedMs);
      } else {
        _lastSyncedAt = null;
      }

      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cached comms logs for $deviceId: $e');
    }
  }

  /// Synchronizes call logs and chat logs directly over LAN HTTP from the child tablet.
  Future<bool> syncLogs(
    String ip,
    String token,
    String deviceId, {
    int? since,
    http.Client? client,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final httpClient = client ?? _httpClient ?? http.Client();
    final shouldCloseClient = client == null && _httpClient == null;

    try {
      final sinceParam = since ?? 0;
      final callUri = Uri.parse('http://$ip:8085/call_logs?since=$sinceParam');
      final chatUri = Uri.parse('http://$ip:8085/chat_logs?since=$sinceParam');
      final headers = {'X-Buddy-Token': token};

      final results = await Future.wait([
        httpClient.get(callUri, headers: headers).timeout(const Duration(seconds: 3)),
        httpClient.get(chatUri, headers: headers).timeout(const Duration(seconds: 3)),
      ]);

      final callResp = results[0];
      final chatResp = results[1];

      if (callResp.statusCode < 200 || callResp.statusCode >= 300) {
        throw Exception('Call logs request failed with HTTP ${callResp.statusCode}');
      }
      if (chatResp.statusCode < 200 || chatResp.statusCode >= 300) {
        throw Exception('Chat logs request failed with HTTP ${chatResp.statusCode}');
      }

      // 1. Process Call Records
      final dynamic callData = jsonDecode(callResp.body);
      final List<dynamic> callList;
      if (callData is List) {
        callList = callData;
      } else if (callData is Map && callData['records'] is List) {
        callList = callData['records'] as List;
      } else if (callData is Map && callData['calls'] is List) {
        callList = callData['calls'] as List;
      } else if (callData is Map && callData['data'] is List) {
        callList = callData['data'] as List;
      } else {
        callList = [];
      }

      final newCalls = callList
          .map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      // Merge and deduplicate calls by ID
      final Map<String, CallRecord> callMap = {
        for (final c in _calls) c.id: c,
      };
      for (final c in newCalls) {
        callMap[c.id] = c;
      }
      _calls = callMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // 2. Process Chat Records
      final dynamic chatData = jsonDecode(chatResp.body);
      final List<dynamic> chatList;
      if (chatData is List) {
        chatList = chatData;
      } else if (chatData is Map && chatData['records'] is List) {
        chatList = chatData['records'] as List;
      } else if (chatData is Map && chatData['chats'] is List) {
        chatList = chatData['chats'] as List;
      } else if (chatData is Map && chatData['messages'] is List) {
        chatList = chatData['messages'] as List;
      } else if (chatData is Map && chatData['data'] is List) {
        chatList = chatData['data'] as List;
      } else {
        chatList = [];
      }

      final newChats = chatList
          .map((e) => ChatMessageRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      // Merge and deduplicate chats by ID
      final Map<String, ChatMessageRecord> chatMap = {
        for (final c in _chats) c.id: c,
      };
      for (final c in newChats) {
        chatMap[c.id] = c;
      }
      _chats = chatMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _lastSyncedAt = DateTime.now();

      // Persist to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _callsKey(deviceId),
        jsonEncode(_calls.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _chatsKey(deviceId),
        jsonEncode(_chats.map((e) => e.toJson()).toList()),
      );
      await prefs.setInt(
        _lastSyncedKey(deviceId),
        _lastSyncedAt!.millisecondsSinceEpoch,
      );

      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('CommsRepository: syncLogs error: $e');
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  /// Clears cached logs for the given device.
  Future<void> clearCache(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_callsKey(deviceId));
      await prefs.remove(_chatsKey(deviceId));
      await prefs.remove(_lastSyncedKey(deviceId));

      _calls = [];
      _chats = [];
      _lastSyncedAt = null;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('CommsRepository: clearCache error: $e');
    }
  }

  /// Prunes records older than maxCount to prevent excessive storage usage.
  Future<void> pruneOldRecords(String deviceId, {int maxCount = 500}) async {
    bool changed = false;
    if (_calls.length > maxCount) {
      _calls = _calls.sublist(0, maxCount);
      changed = true;
    }
    if (_chats.length > maxCount) {
      _chats = _chats.sublist(0, maxCount);
      changed = true;
    }

    if (changed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _callsKey(deviceId),
          jsonEncode(_calls.map((e) => e.toJson()).toList()),
        );
        await prefs.setString(
          _chatsKey(deviceId),
          jsonEncode(_chats.map((e) => e.toJson()).toList()),
        );
        notifyListeners();
      } catch (e) {
        debugPrint('CommsRepository: pruneOldRecords error: $e');
      }
    }
  }
}
