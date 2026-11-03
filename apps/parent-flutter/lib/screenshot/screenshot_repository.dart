import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'screenshot_model.dart';

class ScreenshotRepository extends ChangeNotifier {
  final FirebaseFirestore? _firestore;
  final http.Client? _httpClient;

  List<ScreenshotItem> _history = [];
  bool _isCapturing = false;
  StreamSubscription<QuerySnapshot>? _historySubscription;
  String? _lastError;

  ScreenshotRepository({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
  })  : _firestore = firestore,
        _httpClient = httpClient;

  List<ScreenshotItem> get history => List.unmodifiable(_history);
  bool get isCapturing => _isCapturing;
  ScreenshotItem? get latestScreenshot => _history.isNotEmpty ? _history.first : null;
  String? get lastError => _lastError;
  bool get hasPermissionError => isPermissionDenied(_lastError);

  /// Helper to check if an error represents a Firestore permission-denied error.
  static bool isPermissionDenied(dynamic e) {
    if (e == null) return false;
    if (e is FirebaseException && e.code == 'permission-denied') return true;
    final str = e.toString().toLowerCase();
    return str.contains('permission-denied') ||
        str.contains('permission_denied') ||
        str.contains('cloud_firestore/permission-denied');
  }

  /// Translates Firestore exceptions into friendly, actionable error messages.
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

  FirebaseFirestore? get firestore {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Listens to real-time updates of screenshots for the specified child device
  void subscribeToHistory(String childFcmToken) {
    _historySubscription?.cancel();
    if (childFcmToken.isEmpty || childFcmToken == 'emulator') return;

    final fs = firestore;
    if (fs == null) return;

    try {
      _historySubscription = fs
          .collection('pairings')
          .doc(childFcmToken)
          .collection('screenshots')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .snapshots()
          .listen((snapshot) {
        _history = snapshot.docs
            .map((doc) => ScreenshotItem.fromFirestore(doc))
            .toList();
        notifyListeners();
      }, onError: (e) {
        debugPrint('ScreenshotRepository history subscription error: $e');
        _lastError = formatError(e);
        notifyListeners();
      });
    } catch (e) {
      debugPrint('ScreenshotRepository subscribe error: $e');
      _lastError = formatError(e);
      notifyListeners();
    }
  }

  /// Captures a screenshot from the child device:
  /// 1. Tries direct LAN HTTP if localIpAddress is provided (timeout 5s).
  ///    On success: creates ScreenshotItem, writes it to Firestore pairings/$childFcmToken/screenshots/$id.
  /// 2. Falls back to Firestore command with screenshotRequest (timeout 10s).
  Future<ScreenshotItem?> captureScreenshot(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    if (_isCapturing) return null;

    _isCapturing = true;
    _lastError = null;
    notifyListeners();

    try {
      // Step 1: Direct LAN HTTP
      if (localIpAddress != null && localIpAddress.isNotEmpty) {
        final lanResult = await _captureViaLan(childFcmToken, localIpAddress);
        if (lanResult != null) {
          return lanResult;
        }
      }

      // Step 2: Fallback to Firestore command
      return await _captureViaFirestore(childFcmToken);
    } catch (e) {
      _lastError = formatError(e);
      debugPrint('captureScreenshot error: $e');
      return null;
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<ScreenshotItem?> _captureViaLan(
    String childFcmToken,
    String localIpAddress,
  ) async {
    try {
      final url = Uri.parse('http://$localIpAddress:8085/take_screenshot');
      debugPrint('Attempting direct LAN screenshot request to: $url');

      final client = _httpClient;
      final http.Response response = client != null
          ? await client.post(url).timeout(const Duration(seconds: 5))
          : await http.post(url).timeout(const Duration(seconds: 5));

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

        // Persist to Firestore pairings/$childFcmToken/screenshots/$id
        final fs = firestore;
        if (fs != null && childFcmToken.isNotEmpty && childFcmToken != 'emulator') {
          try {
            await fs
                .collection('pairings')
                .doc(childFcmToken)
                .collection('screenshots')
                .doc(id)
                .set({
              'id': id,
              'timestamp': FieldValue.serverTimestamp(),
              'base64Image': base64Image,
              'deviceModel': ?deviceModel,
              'foregroundApp': ?foregroundApp,
              'foregroundPackage': ?foregroundPackage,
            });
            debugPrint('LAN screenshot successfully persisted to Firestore ($id)');
          } catch (e) {
            debugPrint('Failed to persist LAN screenshot to Firestore: $e');
            if (isPermissionDenied(e)) {
              _lastError = formatError(e);
              notifyListeners();
            }
          }
        }

        // Add to history if not present
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
    }
    return null;
  }

  Future<ScreenshotItem?> _captureViaFirestore(String childFcmToken) async {
    final fs = firestore;
    if (fs == null || childFcmToken.isEmpty || childFcmToken == 'emulator') {
      return null;
    }

    final requestId = const Uuid().v4();
    final completer = Completer<ScreenshotItem?>();
    StreamSubscription<QuerySnapshot>? sub;
    final requestStartTime = DateTime.now();

    try {
      sub = fs
          .collection('pairings')
          .doc(childFcmToken)
          .collection('screenshots')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = (doc.data() as Map<String, dynamic>?) ?? {};
          final docReqId = data['requestId'] as String?;
          final item = ScreenshotItem.fromFirestore(doc);

          if (docReqId == requestId ||
              item.timestamp.isAfter(requestStartTime.subtract(const Duration(seconds: 1)))) {
            if (!completer.isCompleted) {
              completer.complete(item);
            }
          }
        }
      }, onError: (e) {
        debugPrint('Firestore screenshot listener error: $e');
        _lastError = formatError(e);
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      await fs.collection('pairings').doc(childFcmToken).set({
        'screenshotRequest': {
          'requestId': requestId,
          'timestamp': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Firestore screenshot command timed out after 10s');
          _lastError = 'Firestore screenshot command timed out after 10s';
          return null;
        },
      );

      if (result != null) {
        if (!_history.any((h) => h.id == result.id)) {
          _history.insert(0, result);
          notifyListeners();
        }
      }

      return result;
    } catch (e) {
      debugPrint('Firestore captureScreenshot error: $e');
      _lastError = formatError(e);
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  /// Closes the currently active application on the child device.
  /// 1. If localIpAddress is provided, posts to http://$localIpAddress:8085/close_app (timeout 3s).
  /// 2. Fallback / dual-write to Firestore pairings/$childFcmToken:
  ///    closeAppCommand: {'timestamp': FieldValue.serverTimestamp(), 'requestId': Uuid().v4()}
  /// Returns `true` if LAN succeeds or Firestore write succeeds.
  Future<bool> closeCurrentApp(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    bool lanSuccess = false;

    // Step 1: Direct LAN HTTP
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      try {
        final url = Uri.parse('http://$localIpAddress:8085/close_app');
        debugPrint('Attempting direct LAN close_app to: $url');

        final client = _httpClient;
        final http.Response response = client != null
            ? await client.post(url).timeout(const Duration(seconds: 3))
            : await http.post(url).timeout(const Duration(seconds: 3));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          lanSuccess = true;
          debugPrint('Direct LAN close_app succeeded ($localIpAddress)');
        } else {
          debugPrint('Direct LAN close_app failed with status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Direct LAN close_app error: $e');
      }
    }

    // Step 2: Fallback / dual-write to Firestore
    bool firestoreSuccess = false;
    final fs = firestore;
    if (fs != null && childFcmToken.isNotEmpty && childFcmToken != 'emulator') {
      try {
        final requestId = const Uuid().v4();
        await fs.collection('pairings').doc(childFcmToken).set({
          'closeAppCommand': {
            'timestamp': FieldValue.serverTimestamp(),
            'requestId': requestId,
          },
        }, SetOptions(merge: true));
        firestoreSuccess = true;
        debugPrint('Firestore closeAppCommand successfully written ($requestId)');
      } catch (e) {
        debugPrint('Firestore closeCurrentApp error: $e');
        if (isPermissionDenied(e)) {
          _lastError = formatError(e);
          notifyListeners();
        }
      }
    }

    return lanSuccess || firestoreSuccess;
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    super.dispose();
  }
}
