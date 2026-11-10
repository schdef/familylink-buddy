import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'screenshot_model.dart';

class ScreenshotRepository extends ChangeNotifier {
  final http.Client? _httpClient;

  List<ScreenshotItem> _history = [];
  bool _isCapturing = false;
  String? _lastError;
  String? _activeChildToken;
  String? _localIpAddress;

  ScreenshotRepository({
    http.Client? httpClient,
    dynamic firestore,
  }) : _httpClient = httpClient;

  List<ScreenshotItem> get history => List.unmodifiable(_history);
  List<ScreenshotItem> get screenshots => List.unmodifiable(_history);
  bool get isCapturing => _isCapturing;
  ScreenshotItem? get latestScreenshot => _history.isNotEmpty ? _history.first : null;
  String? get lastError => _lastError;
  bool get hasPermissionError => isPermissionDenied(_lastError);
  String? get localIpAddress => _localIpAddress;

  set localIpAddress(String? ip) {
    _localIpAddress = ip;
    notifyListeners();
  }

  /// Helper to check if an error represents a permission-denied error.
  static bool isPermissionDenied(dynamic e) {
    if (e == null) return false;
    final str = e.toString().toLowerCase();
    return str.contains('permission-denied') ||
        str.contains('permission_denied');
  }

  /// Translates exceptions into friendly, actionable error messages.
  static String formatError(dynamic e) {
    if (e == null) return '';
    if (isPermissionDenied(e)) {
      return 'Firestore-Berechtigung verweigert (permission-denied): Die Firestore Security Rules für "screenshots" (pairings/{childToken}/screenshots) müssen in der Firebase Console aktualisiert werden.';
    }
    return e.toString();
  }

  @visibleForTesting
  set lastErrorForTesting(String? value) {
    _lastError = value;
    notifyListeners();
  }

  @visibleForTesting
  set isCapturingForTesting(bool value) {
    _isCapturing = value;
    notifyListeners();
  }

  @visibleForTesting
  void setHistoryForTesting(List<ScreenshotItem> items) {
    _history = List.from(items);
    notifyListeners();
  }

  /// Listens to updates of screenshots (in Local-First mode, managed in memory/device)
  void subscribeToHistory(String childFcmToken, {String? localIpAddress}) {
    _activeChildToken = childFcmToken;
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      _localIpAddress = localIpAddress;
    }
  }

  String _resolveHost(String? localIpAddress, String childToken) {
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      return localIpAddress;
    }
    if (_localIpAddress != null && _localIpAddress!.isNotEmpty) {
      return _localIpAddress!;
    }
    if (childToken == 'emulator') {
      return '10.0.2.2';
    }
    if (childToken.contains('.')) {
      return childToken;
    }
    return childToken;
  }

  /// Captures a screenshot from the child device purely via LAN HTTP http://$localIpAddress:8085/take_screenshot
  Future<ScreenshotItem?> captureScreenshot(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    if (_isCapturing) return null;

    _isCapturing = true;
    _lastError = null;
    notifyListeners();

    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/take_screenshot');
      debugPrint('ScreenshotRepository: Attempting direct LAN screenshot request to: $url');

      final client = _httpClient;
      final http.Response response = client != null
          ? await client.post(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 12))
          : await http.post(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = jsonDecode(response.body);
        final Map<String, dynamic> json;
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        } else if (decoded is String) {
          json = {'base64Image': decoded};
        } else {
          json = {};
        }

        final id = (json['id'] as String?)?.isNotEmpty == true
            ? json['id'] as String
            : const Uuid().v4();

        final base64Image =
            (json['base64Image'] ?? json['image'] ?? json['screenshot'] ?? '') as String;
        final deviceModel = json['deviceModel'] as String?;
        final foregroundApp = json['foregroundApp'] as String?;
        final foregroundPackage = json['foregroundPackage'] as String?;

        DateTime timestamp;
        if (json['timestamp'] is int) {
          timestamp = DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int);
        } else if (json['timestamp'] is String) {
          timestamp = DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now();
        } else {
          timestamp = DateTime.now();
        }

        final item = ScreenshotItem(
          id: id,
          timestamp: timestamp,
          base64Image: base64Image,
          deviceModel: deviceModel,
          foregroundApp: foregroundApp,
          foregroundPackage: foregroundPackage,
        );

        if (!_history.any((h) => h.id == item.id)) {
          _history.insert(0, item);
          notifyListeners();
        }

        return item;
      } else {
        debugPrint('Direct LAN screenshot failed with status: ${response.statusCode}');
        try {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['message'] != null) {
            _lastError = decoded['message'].toString();
          } else {
            _lastError = 'HTTP ${response.statusCode}: ${response.body}';
          }
        } catch (_) {
          _lastError = 'HTTP ${response.statusCode}';
        }
      }
    } catch (e) {
      debugPrint('Direct LAN screenshot error: $e');
      _lastError = formatError(e);
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
    return null;
  }

  /// Takes a silent camera photo on the child device purely via LAN HTTP http://$localIpAddress:8085/take_camera_photo
  Future<ScreenshotItem?> takeCameraPhoto({
    String? childFcmToken,
    String? localIpAddress,
    String facing = 'front',
    bool flash = false,
  }) async {
    if (_isCapturing) return null;

    _isCapturing = true;
    _lastError = null;
    notifyListeners();

    try {
      final token = (childFcmToken != null && childFcmToken.isNotEmpty)
          ? childFcmToken
          : (_activeChildToken ?? '');
      final host = _resolveHost(localIpAddress, token);
      final url = Uri.parse('http://$host:8085/take_camera_photo?facing=$facing&flash=$flash');
      debugPrint('ScreenshotRepository: Attempting direct LAN camera photo request to: $url');

      final client = _httpClient;
      final http.Response response = client != null
          ? await client.post(url, headers: {'X-Buddy-Token': token}).timeout(const Duration(seconds: 12))
          : await http.post(url, headers: {'X-Buddy-Token': token}).timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = jsonDecode(response.body);
        final Map<String, dynamic> json;
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        } else if (decoded is String) {
          json = {'base64Image': decoded};
        } else {
          json = {};
        }

        final id = (json['id'] as String?)?.isNotEmpty == true
            ? json['id'] as String
            : const Uuid().v4();

        final base64Image =
            (json['base64Image'] ?? json['image'] ?? json['screenshot'] ?? '') as String;
        final deviceModel = json['deviceModel'] as String?;
        final foregroundApp = json['foregroundApp'] as String?;
        final foregroundPackage = json['foregroundPackage'] as String?;

        DateTime timestamp;
        if (json['timestamp'] is int) {
          timestamp = DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int);
        } else if (json['timestamp'] is String) {
          timestamp = DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now();
        } else {
          timestamp = DateTime.now();
        }

        final item = ScreenshotItem(
          id: id,
          timestamp: timestamp,
          base64Image: base64Image,
          deviceModel: deviceModel,
          foregroundApp: foregroundApp,
          foregroundPackage: foregroundPackage,
          captureType: 'camera',
          facing: facing,
          flash: flash,
        );

        if (!_history.any((h) => h.id == item.id)) {
          _history.insert(0, item);
          notifyListeners();
        }

        return item;
      } else {
        debugPrint('Direct LAN camera photo failed with status: ${response.statusCode}');
        try {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['message'] != null) {
            _lastError = decoded['message'].toString();
          } else {
            _lastError = 'HTTP ${response.statusCode}: ${response.body}';
          }
        } catch (_) {
          _lastError = 'HTTP ${response.statusCode}';
        }
      }
    } catch (e) {
      debugPrint('Direct LAN camera photo error: $e');
      _lastError = formatError(e);
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
    return null;
  }

  /// Closes the currently active application on the child device via pure LAN HTTP
  Future<bool> closeCurrentApp(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/close_app');
      debugPrint('ScreenshotRepository: Attempting direct LAN close_app to: $url');

      final client = _httpClient;
      final http.Response response = client != null
          ? await client.post(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3))
          : await http.post(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Direct LAN close_app succeeded ($host)');
        return true;
      } else {
        debugPrint('Direct LAN close_app failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Direct LAN close_app error: $e');
      return false;
    }
  }

  /// Locks the tablet screen of the child device via pure LAN HTTP
  Future<bool> lockScreen(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/lock_screen');
      debugPrint('ScreenshotRepository: Attempting direct LAN lock_screen to: $url');

      final client = _httpClient;
      final http.Response response = client != null
          ? await client.post(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3))
          : await http.post(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Direct LAN lock_screen succeeded ($host)');
        return true;
      } else {
        debugPrint('Direct LAN lock_screen failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Direct LAN lock_screen error: $e');
      _lastError = formatError(e);
      notifyListeners();
      return false;
    }
  }

  /// Deletes a single screenshot and removes it from local history.
  Future<bool> deleteScreenshot(String childFcmToken, String screenshotId) async {
    _lastError = null;
    _history.removeWhere((item) => item.id == screenshotId);
    notifyListeners();
    return true;
  }

  /// Deletes all screenshots and clears local history.
  Future<bool> deleteAllScreenshots(String childFcmToken) async {
    _lastError = null;
    _history.clear();
    notifyListeners();
    return true;
  }
}
