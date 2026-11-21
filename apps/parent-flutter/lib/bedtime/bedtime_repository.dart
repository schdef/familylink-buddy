import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'bedtime_schedule.dart';

class BedtimeRepository extends ChangeNotifier {
  final http.Client? _httpClient;
  final SharedPreferences? _prefs;

  BedtimeSchedule _schedule = const BedtimeSchedule();
  Timer? _pollingTimer;
  bool _isDisposed = false;

  BedtimeRepository({
    http.Client? httpClient,
    SharedPreferences? prefs,
    dynamic firestore,
  })  : _httpClient = httpClient,
        _prefs = prefs;

  BedtimeSchedule get schedule => _schedule;

  @visibleForTesting
  set schedule(BedtimeSchedule value) {
    _schedule = value;
    notifyListeners();
  }

  static String cacheKey(String childToken) => 'cached_bedtime_schedule_$childToken';

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('BedtimeRepository: error getting SharedPreferences: $e');
      return null;
    }
  }

  Future<void> _loadCache(String childToken) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;
      final raw = prefs.getString(cacheKey(childToken));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _schedule = BedtimeSchedule.fromJson(decoded);
          notifyListeners();
        } else if (decoded is Map) {
          _schedule = BedtimeSchedule.fromJson(Map<String, dynamic>.from(decoded));
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('BedtimeRepository: _loadCache error: $e');
    }
  }

  Future<void> _saveCache(String childToken) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;
      final jsonStr = jsonEncode(_schedule.toJson());
      await prefs.setString(cacheKey(childToken), jsonStr);
    } catch (e) {
      debugPrint('BedtimeRepository: _saveCache error: $e');
    }
  }

  @visibleForTesting
  Future<void> loadCache(String childToken) => _loadCache(childToken);

  @visibleForTesting
  Future<void> saveCache(String childToken) => _saveCache(childToken);

  @visibleForTesting
  Timer? get pollingTimer => _pollingTimer;

  String _resolveHost(String? localIpAddress, String childToken) {
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      return localIpAddress;
    }
    if (childToken == 'emulator') {
      return '10.0.2.2';
    }
    if (childToken.contains('.')) {
      return childToken;
    }
    return '10.0.2.2';
  }

  /// Starts listening to device schedule over LAN with initial cache load and periodic polling
  Future<void> subscribeToDevice(String childFcmToken, {String? localIpAddress}) async {
    await _loadCache(childFcmToken);
    fetchSchedule(childFcmToken, localIpAddress: localIpAddress);

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => fetchSchedule(childFcmToken, localIpAddress: localIpAddress),
    );
  }

  /// Stops background polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopPolling();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// Fetches bedtime schedule from child device via GET /get_schedule over LAN
  Future<bool> fetchSchedule(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/get_schedule');
      final client = _httpClient;
      final response = client != null
          ? await client.get(
              url,
              headers: {'X-Buddy-Token': childFcmToken},
            ).timeout(const Duration(seconds: 3))
          : await http.get(
              url,
              headers: {'X-Buddy-Token': childFcmToken},
            ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final Map<String, dynamic> scheduleMap;
          if (data.containsKey('schedule') && data['schedule'] is Map) {
            scheduleMap = Map<String, dynamic>.from(data['schedule'] as Map);
          } else {
            scheduleMap = Map<String, dynamic>.from(data);
          }
          _schedule = BedtimeSchedule.fromJson(scheduleMap);
          notifyListeners();
          await _saveCache(childFcmToken);
          return true;
        }
      }
    } catch (e) {
      debugPrint('BedtimeRepository: fetchSchedule error: $e');
    }
    return false;
  }

  /// Saves the schedule directly via REST endpoint http://$localIpAddress:8085/set_schedule
  Future<bool> saveSchedule(
    String childFcmToken,
    BedtimeSchedule newSchedule, {
    String? localIpAddress,
  }) async {
    _schedule = newSchedule;
    notifyListeners();
    await _saveCache(childFcmToken);

    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/set_schedule');
      final client = _httpClient;
      final response = client != null
          ? await client.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: jsonEncode(newSchedule.toJson()),
            ).timeout(const Duration(seconds: 3))
          : await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: jsonEncode(newSchedule.toJson()),
            ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Direct HTTP set_schedule succeeded ($host)');
        return true;
      }
    } catch (e) {
      debugPrint('Direct HTTP set_schedule error: $e');
    }

    return false;
  }

  /// Toggles manual Wi-Fi block status via http://$localIpAddress:8085/toggle_wifi?block=$block
  Future<bool> toggleManualBlock(
    String childFcmToken,
    bool block, {
    String? localIpAddress,
  }) async {
    _schedule = _schedule.copyWith(isCurrentlyBlocked: block);
    notifyListeners();
    await _saveCache(childFcmToken);

    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/toggle_wifi?block=$block');
      final client = _httpClient;
      final response = client != null
          ? await client.post(
              url,
              headers: {'X-Buddy-Token': childFcmToken},
            ).timeout(const Duration(seconds: 3))
          : await http.post(
              url,
              headers: {'X-Buddy-Token': childFcmToken},
            ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Direct HTTP toggle_wifi succeeded ($host): block=$block');
        return true;
      }
    } catch (e) {
      debugPrint('Direct HTTP toggle_wifi error: $e');
    }

    return false;
  }
}
