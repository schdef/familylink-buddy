import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'bedtime_schedule.dart';

class BedtimeRepository extends ChangeNotifier {
  BedtimeSchedule _schedule = const BedtimeSchedule();

  BedtimeRepository({dynamic firestore});

  BedtimeSchedule get schedule => _schedule;

  @visibleForTesting
  set schedule(BedtimeSchedule value) {
    _schedule = value;
    notifyListeners();
  }

  void subscribeToDevice(String childFcmToken) {
    // Local-First: schedule is maintained locally and synced directly over LAN
  }

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

  /// Saves the schedule directly via REST endpoint http://$localIpAddress:8085/set_schedule
  Future<bool> saveSchedule(
    String childFcmToken,
    BedtimeSchedule newSchedule, {
    String? localIpAddress,
  }) async {
    _schedule = newSchedule;
    notifyListeners();

    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/set_schedule');
      final response = await http.post(
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

    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/toggle_wifi?block=$block');
      final response = await http.post(
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
