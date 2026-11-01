import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'bedtime_schedule.dart';

class BedtimeRepository extends ChangeNotifier {
  FirebaseFirestore? _firestore;
  BedtimeSchedule _schedule = const BedtimeSchedule();
  StreamSubscription<DocumentSnapshot>? _subscription;

  BedtimeRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  BedtimeSchedule get schedule => _schedule;

  @visibleForTesting
  set schedule(BedtimeSchedule value) {
    _schedule = value;
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

  /// Listens to real-time changes of the bedtime schedule and Wi-Fi state for the child device
  void subscribeToDevice(String childFcmToken) {
    _subscription?.cancel();
    if (childFcmToken.isEmpty || childFcmToken == 'emulator') return;

    final fs = firestore;
    if (fs == null) return;

    try {
      _subscription = fs
          .collection('pairings')
          .doc(childFcmToken)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            final scheduleMap = data['bedtimeSchedule'] as Map<dynamic, dynamic>?;
            if (scheduleMap != null) {
              _schedule = BedtimeSchedule.fromJson(Map<String, dynamic>.from(scheduleMap));
            }

            if (data.containsKey('manualWifiBlock')) {
              final isManualBlocked = data['manualWifiBlock'] as bool? ?? false;
              _schedule = _schedule.copyWith(isCurrentlyBlocked: isManualBlocked);
            }
            notifyListeners();
          }
        }
      }, onError: (e) {
        debugPrint('BedtimeRepository subscription error: $e');
      });
    } catch (e) {
      debugPrint('BedtimeRepository firestore subscribe error: $e');
    }
  }

  /// Saves the schedule to Firestore pairings/{childFcmToken} under bedtimeSchedule.
  /// If localIpAddress is provided, posts to direct REST endpoint http://$localIpAddress:8085/set_schedule.
  Future<bool> saveSchedule(
    String childFcmToken,
    BedtimeSchedule newSchedule, {
    String? localIpAddress,
  }) async {
    _schedule = newSchedule;
    notifyListeners();

    bool directSuccess = false;

    // Direct HTTP push
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      try {
        final url = Uri.parse('http://$localIpAddress:8085/set_schedule');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(newSchedule.toJson()),
        ).timeout(const Duration(seconds: 2));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          directSuccess = true;
          debugPrint('Direct HTTP set_schedule succeeded ($localIpAddress)');
        }
      } catch (e) {
        debugPrint('Direct HTTP set_schedule error: $e');
      }
    }

    // Firestore sync
    bool firestoreSuccess = false;
    final fs = firestore;
    if (fs != null && childFcmToken.isNotEmpty) {
      try {
        await fs.collection('pairings').doc(childFcmToken).set({
          'bedtimeSchedule': newSchedule.toJson(),
        }, SetOptions(merge: true));
        firestoreSuccess = true;
      } catch (e) {
        debugPrint('Firestore saveSchedule error: $e');
      }
    }

    return directSuccess || firestoreSuccess;
  }

  /// Toggles manual Wi-Fi block status.
  /// Writes manualWifiBlock: block to Firestore and posts to http://$localIpAddress:8085/toggle_wifi?block=$block.
  Future<bool> toggleManualBlock(
    String childFcmToken,
    bool block, {
    String? localIpAddress,
  }) async {
    _schedule = _schedule.copyWith(isCurrentlyBlocked: block);
    notifyListeners();

    bool directSuccess = false;

    // Direct HTTP push
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      try {
        final url = Uri.parse('http://$localIpAddress:8085/toggle_wifi?block=$block');
        final response = await http.post(url).timeout(const Duration(seconds: 2));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          directSuccess = true;
          debugPrint('Direct HTTP toggle_wifi succeeded ($localIpAddress): block=$block');
        }
      } catch (e) {
        debugPrint('Direct HTTP toggle_wifi error: $e');
      }
    }

    // Firestore sync
    bool firestoreSuccess = false;
    final fs = firestore;
    if (fs != null && childFcmToken.isNotEmpty) {
      try {
        await fs.collection('pairings').doc(childFcmToken).set({
          'manualWifiBlock': block,
          'bedtimeSchedule': {
            'isCurrentlyBlocked': block,
          },
        }, SetOptions(merge: true));
        firestoreSuccess = true;
      } catch (e) {
        debugPrint('Firestore toggleManualBlock error: $e');
      }
    }

    return directSuccess || firestoreSuccess;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
