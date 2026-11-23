import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../pairing/lan_discovery_service.dart';
import '../pairing/pairing_repository.dart';

class VolumeState {
  final int mediaVolume;
  final int ringtoneVolume;
  final int alarmVolume;
  final int maxMediaVolume;
  final int maxRingtoneVolume;
  final int maxAlarmVolume;
  final bool isMuted;
  final bool isMusicActive;
  final String? mediaTitle;
  final String? mediaArtist;
  final String? mediaPackage;
  final DateTime? timestamp;

  const VolumeState({
    this.mediaVolume = -1,
    this.ringtoneVolume = -1,
    this.alarmVolume = -1,
    this.maxMediaVolume = 15,
    this.maxRingtoneVolume = 15,
    this.maxAlarmVolume = 15,
    this.isMuted = false,
    this.isMusicActive = false,
    this.mediaTitle,
    this.mediaArtist,
    this.mediaPackage,
    this.timestamp,
  });

  static String? _normalizeString(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  factory VolumeState.fromJson(Map<String, dynamic> json) {
    return VolumeState(
      mediaVolume: json['mediaVolume'] as int? ?? -1,
      ringtoneVolume: json['ringtoneVolume'] as int? ?? -1,
      alarmVolume: json['alarmVolume'] as int? ?? -1,
      maxMediaVolume: json['maxMediaVolume'] as int? ?? 15,
      maxRingtoneVolume: json['maxRingtoneVolume'] as int? ?? 15,
      maxAlarmVolume: json['maxAlarmVolume'] as int? ?? 15,
      isMuted: json['isMuted'] as bool? ?? false,
      isMusicActive: json['isMusicActive'] as bool? ?? false,
      mediaTitle: _normalizeString(json['mediaTitle'] ?? json['trackTitle']),
      mediaArtist: _normalizeString(json['mediaArtist'] ?? json['artist']),
      mediaPackage: _normalizeString(json['mediaPackage'] ?? json['packageName']),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : null,
    );
  }

  VolumeState copyWith({
    int? mediaVolume,
    int? ringtoneVolume,
    int? alarmVolume,
    int? maxMediaVolume,
    int? maxRingtoneVolume,
    int? maxAlarmVolume,
    bool? isMuted,
    bool? isMusicActive,
    String? mediaTitle,
    String? mediaArtist,
    String? mediaPackage,
    DateTime? timestamp,
  }) {
    return VolumeState(
      mediaVolume: mediaVolume ?? this.mediaVolume,
      ringtoneVolume: ringtoneVolume ?? this.ringtoneVolume,
      alarmVolume: alarmVolume ?? this.alarmVolume,
      maxMediaVolume: maxMediaVolume ?? this.maxMediaVolume,
      maxRingtoneVolume: maxRingtoneVolume ?? this.maxRingtoneVolume,
      maxAlarmVolume: maxAlarmVolume ?? this.maxAlarmVolume,
      isMuted: isMuted ?? this.isMuted,
      isMusicActive: isMusicActive ?? this.isMusicActive,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      mediaArtist: mediaArtist ?? this.mediaArtist,
      mediaPackage: mediaPackage ?? this.mediaPackage,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  bool get isKnown => mediaVolume >= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VolumeState &&
        other.mediaVolume == mediaVolume &&
        other.ringtoneVolume == ringtoneVolume &&
        other.alarmVolume == alarmVolume &&
        other.maxMediaVolume == maxMediaVolume &&
        other.maxRingtoneVolume == maxRingtoneVolume &&
        other.maxAlarmVolume == maxAlarmVolume &&
        other.isMuted == isMuted &&
        other.isMusicActive == isMusicActive &&
        other.mediaTitle == mediaTitle &&
        other.mediaArtist == mediaArtist &&
        other.mediaPackage == mediaPackage;
  }

  @override
  int get hashCode => Object.hash(
        mediaVolume,
        ringtoneVolume,
        alarmVolume,
        maxMediaVolume,
        maxRingtoneVolume,
        maxAlarmVolume,
        isMuted,
        isMusicActive,
        mediaTitle,
        mediaArtist,
        mediaPackage,
      );
}

class VolumeRepository extends ChangeNotifier {
  static const Duration defaultPollingInterval = Duration(seconds: 5);
  static const Duration activePollingInterval = Duration(seconds: 3);

  final http.Client? _httpClient;
  VolumeState _volumeState = const VolumeState();
  bool _isConnected = false;
  DateTime? _lastSeen;
  String? _localIpAddress;
  Timer? _pollingTimer;
  Duration _currentPollingInterval = defaultPollingInterval;
  String? _activeChildToken;
  LanDiscoveryService? _lanDiscoveryService;
  PairingRepository? _pairingRepository;
  String? _deviceId;
  bool _isRediscovering = false;

  VolumeRepository({http.Client? httpClient}) : _httpClient = httpClient;

  VolumeState get volumeState => _volumeState;
  bool get isConnected => _isConnected;
  DateTime? get lastSeen => _lastSeen;
  String? get localIpAddress => _localIpAddress;
  Duration get currentPollingInterval => _currentPollingInterval;

  set localIpAddress(String? ip) {
    _localIpAddress = ip;
    notifyListeners();
  }

  void setDiscoveryDependencies({
    LanDiscoveryService? lanDiscoveryService,
    PairingRepository? pairingRepository,
    String? deviceId,
  }) {
    _lanDiscoveryService = lanDiscoveryService;
    _pairingRepository = pairingRepository;
    _deviceId = deviceId;
  }

  /// Initialize the repository (no cloud/Firebase required)
  Future<void> initialize() async {
    // Local-First LAN initialization
  }

  /// Starts monitoring and polling the child device over LAN
  void subscribeToDevice(
    String childFcmToken, {
    String? ipAddress,
    String? deviceId,
    PairingRepository? pairingRepo,
    LanDiscoveryService? discoveryService,
  }) {
    _activeChildToken = childFcmToken;
    if (deviceId != null) _deviceId = deviceId;
    if (pairingRepo != null) _pairingRepository = pairingRepo;
    if (discoveryService != null) _lanDiscoveryService = discoveryService;
    if (ipAddress != null && ipAddress.isNotEmpty) {
      _localIpAddress = ipAddress;
    } else if ((_localIpAddress == null || _localIpAddress!.isEmpty) && childFcmToken.contains('.')) {
      _localIpAddress = childFcmToken;
    }

    _pollingTimer?.cancel();
    _currentPollingInterval = _volumeState.isMusicActive ? activePollingInterval : defaultPollingInterval;
    _startPolling();

    // Initial fetch
    _pollVolumeReport(childFcmToken);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_currentPollingInterval, (_) {
      if (_activeChildToken != null && _activeChildToken!.isNotEmpty) {
        _pollVolumeReport(_activeChildToken!);
      }
    });
  }

  void _updatePollingInterval(bool isMusicActive) {
    final targetInterval = isMusicActive ? activePollingInterval : defaultPollingInterval;
    if (_currentPollingInterval != targetInterval) {
      _currentPollingInterval = targetInterval;
      if (_pollingTimer != null) {
        _startPolling();
      }
    }
  }

  /// Stop background polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  String _resolveHost(String childToken) {
    if (_localIpAddress != null && _localIpAddress!.isNotEmpty) {
      return _localIpAddress!;
    }
    if (childToken == 'emulator') {
      return '10.0.2.2';
    }
    if (childToken.contains('.')) {
      return childToken;
    }
    return '10.0.2.2';
  }

  @visibleForTesting
  set volumeStateForTesting(VolumeState state) {
    _volumeState = state;
    _updatePollingInterval(state.isMusicActive);
    notifyListeners();
  }

  void _updateVolumeStateLocally(String stream, int level) {
    _volumeState = _volumeState.copyWith(
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
    _updatePollingInterval(_volumeState.isMusicActive);
    notifyListeners();
  }

  /// Send a SET_VOLUME command to the child device via pure LAN HTTP
  Future<bool> setVolume({
    required String childFcmToken,
    required String stream, // MEDIA | RINGTONE | ALARM | ALL
    required int level,
  }) async {
    final host = _resolveHost(childFcmToken);
    try {
      final url = Uri.parse('http://$host:8085/set_volume?stream=$stream&level=$level');
      debugPrint('VolumeRepository: Sending LAN set_volume to $url');
      final body = jsonEncode({'stream': stream, 'level': level});
      final headers = {
        'Content-Type': 'application/json',
        'X-Buddy-Token': childFcmToken,
      };
      final client = _httpClient;
      final response = client != null
          ? await client.post(url, headers: headers, body: body).timeout(const Duration(seconds: 3))
          : await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        bool stateUpdated = false;
        try {
          if (response.body.isNotEmpty) {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
              if (data.containsKey('mediaVolume')) {
                final parsed = VolumeState.fromJson(data);
                _volumeState = parsed.timestamp == null
                    ? parsed.copyWith(timestamp: DateTime.now())
                    : parsed;
                _isConnected = true;
                _lastSeen = DateTime.now();
                stateUpdated = true;
                _updatePollingInterval(_volumeState.isMusicActive);
                notifyListeners();
              } else if (data.containsKey('level')) {
                final respLevel = (data['level'] as num).toInt();
                final respStream = (data['stream'] as String?) ?? stream;
                _updateVolumeStateLocally(respStream, respLevel);
                stateUpdated = true;
              }
            }
          }
        } catch (_) {
          // Fall back to local update
        }
        if (!stateUpdated) {
          _updateVolumeStateLocally(stream, level);
        }
        return true;
      } else {
        debugPrint('VolumeRepository: LAN set_volume failed with HTTP ${response.statusCode}');
        _handleUnreachable(childFcmToken);
        return false;
      }
    } catch (e) {
      debugPrint('VolumeRepository: LAN set_volume error: $e');
      _handleUnreachable(childFcmToken);
      return false;
    }
  }

  /// Request a volume report from the child device via pure LAN HTTP
  Future<void> requestVolumeReport(String childFcmToken) async {
    final host = _resolveHost(childFcmToken);
    try {
      final url = Uri.parse('http://$host:8085/volume_report');
      final client = _httpClient;
      final response = client != null
          ? await client.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3))
          : await http.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _volumeState = VolumeState.fromJson(data);
        _isConnected = true;
        _lastSeen = DateTime.now();
        _updatePollingInterval(_volumeState.isMusicActive);
        notifyListeners();
      } else {
        debugPrint('VolumeRepository: LAN volume_report failed with HTTP ${response.statusCode}');
        _handleUnreachable(childFcmToken);
      }
    } catch (e) {
      debugPrint('VolumeRepository: LAN volume_report error: $e');
      _handleUnreachable(childFcmToken);
    }
  }

  /// Polls the volume and music status from the child device (alias for requestVolumeReport)
  Future<void> _pollVolumeReport(String childFcmToken) => requestVolumeReport(childFcmToken);

  /// Stop active media/audio playback (e.g. Spotify) on child device via LAN HTTP
  Future<bool> stopAudioPlayback({String? childToken}) async {
    final token = (childToken != null && childToken.isNotEmpty)
        ? childToken
        : (_activeChildToken ?? '');
    final host = _resolveHost(token);
    try {
      final url = Uri.parse('http://$host:8085/stop_audio');
      debugPrint('VolumeRepository: Sending LAN stop_audio to $url');
      final client = _httpClient;
      final response = client != null
          ? await client.post(url, headers: {'X-Buddy-Token': token}).timeout(const Duration(seconds: 3))
          : await http.post(url, headers: {'X-Buddy-Token': token}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _volumeState = _volumeState.copyWith(
          isMusicActive: false,
          mediaTitle: null,
          mediaArtist: null,
          mediaPackage: null,
          timestamp: DateTime.now(),
        );
        _isConnected = true;
        _lastSeen = DateTime.now();
        _updatePollingInterval(false);
        notifyListeners();
        return true;
      } else {
        debugPrint('VolumeRepository: LAN stop_audio failed with HTTP ${response.statusCode}');
        _handleUnreachable(token);
        return false;
      }
    } catch (e) {
      debugPrint('VolumeRepository: LAN stop_audio error: $e');
      _handleUnreachable(token);
      return false;
    }
  }

  Future<void> _handleUnreachable(String childToken) async {
    _isConnected = false;
    notifyListeners();

    if (_isRediscovering) return;
    final devId = _deviceId;
    final repo = _pairingRepository;
    if (devId == null || devId.isEmpty || repo == null) return;

    _isRediscovering = true;
    try {
      final service = _lanDiscoveryService ?? LanDiscoveryService();
      final newIp = await service.rediscoverDevice(
        deviceId: devId,
        token: childToken,
        pairingRepository: repo,
        volumeRepository: this,
      );
      if (newIp != null) {
        debugPrint('VolumeRepository: Re-discovered device at $newIp');
      }
    } catch (e) {
      debugPrint('VolumeRepository: Error during re-discovery: $e');
    } finally {
      _isRediscovering = false;
    }
  }

  static String getLastSeenText(DateTime? lastSeen, {DateTime? now, dynamic strings}) {
    if (strings != null) {
      if (lastSeen == null) return strings.lastSeenNever as String;
      final referenceTime = now ?? DateTime.now();
      final diff = referenceTime.difference(lastSeen);
      if (diff.inSeconds < 10) {
        return strings.lastSeenJustNow as String;
      } else if (diff.inSeconds < 60) {
        return strings.lastSeenSecondsAgo(diff.inSeconds) as String;
      } else if (diff.inMinutes < 60) {
        return strings.lastSeenMinutesAgo(diff.inMinutes) as String;
      } else {
        final hours = diff.inHours;
        if (hours < 24) {
          return strings.lastSeenHoursAgo(hours) as String;
        } else {
          return strings.lastSeenDaysAgo(diff.inDays) as String;
        }
      }
    }

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

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
