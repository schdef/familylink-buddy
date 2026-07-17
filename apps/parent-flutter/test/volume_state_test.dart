import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/volume/volume_repository.dart';

void main() {
  group('VolumeState Tests', () {
    test('Default values', () {
      const state = VolumeState();
      expect(state.mediaVolume, -1);
      expect(state.ringtoneVolume, -1);
      expect(state.alarmVolume, -1);
      expect(state.maxMediaVolume, 15);
      expect(state.maxRingtoneVolume, 15);
      expect(state.maxAlarmVolume, 15);
      expect(state.isMuted, false);
      expect(state.timestamp, null);
      expect(state.isKnown, false);
    });

    test('fromJson parsing', () {
      final json = {
        'mediaVolume': 5,
        'ringtoneVolume': 7,
        'alarmVolume': 10,
        'maxMediaVolume': 15,
        'maxRingtoneVolume': 15,
        'maxAlarmVolume': 15,
        'isMuted': false,
        'timestamp': 1680000000000,
      };

      final state = VolumeState.fromJson(json);
      expect(state.mediaVolume, 5);
      expect(state.ringtoneVolume, 7);
      expect(state.alarmVolume, 10);
      expect(state.isMuted, false);
      expect(state.timestamp, DateTime.fromMillisecondsSinceEpoch(1680000000000));
      expect(state.isKnown, true);
    });

    test('fromJson parsing with nulls / missing values', () {
      final json = <String, dynamic>{};
      final state = VolumeState.fromJson(json);
      expect(state.mediaVolume, -1);
      expect(state.maxMediaVolume, 15);
      expect(state.isMuted, false);
      expect(state.timestamp, null);
    });
  });

  group('VolumeRepository Direct Wi-Fi REST API Tests', () {
    test('setVolume attempts direct REST API and succeeds', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        final result = await repo.setVolume(
          childFcmToken: 'some_token',
          stream: 'MEDIA',
          level: 8,
        );

        expect(result, isTrue);
        expect(repo.volumeState.mediaVolume, 8);
        expect(repo.isConnected, isTrue);
      }, () => MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.100:8085/set_volume?stream=MEDIA&level=8');
        expect(request.method, 'POST');
        return http.Response(jsonEncode({'status': 'success'}), 200);
      }));
    });

    test('requestVolumeReport attempts direct REST API and succeeds', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        await repo.requestVolumeReport('some_token');

        expect(repo.volumeState.mediaVolume, 5);
        expect(repo.volumeState.ringtoneVolume, 7);
        expect(repo.isConnected, isTrue);
      }, () => MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.100:8085/volume_report');
        expect(request.method, 'GET');
        return http.Response(jsonEncode({
          'mediaVolume': 5,
          'ringtoneVolume': 7,
          'alarmVolume': 10,
          'maxMediaVolume': 15,
          'maxRingtoneVolume': 15,
          'maxAlarmVolume': 15,
          'isMuted': false,
        }), 200);
      }));
    });

    test('setVolume falls back to Firestore when direct REST API fails', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        final result = await repo.setVolume(
          childFcmToken: 'some_token',
          stream: 'MEDIA',
          level: 8,
        );

        // It falls back to Firestore, which catches the exception and returns false
        expect(result, isFalse);
      }, () => MockClient((request) async {
        return http.Response('Error', 500);
      }));
    });

    test('requestVolumeReport falls back to Firestore when direct REST API fails', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        // Direct REST fails, falls back to Firestore, which throws core/no-app and is caught internally.
        // We verify that the method executes without throwing externally.
        await repo.requestVolumeReport('some_token');
        expect(repo.isConnected, isFalse);
      }, () => MockClient((request) async {
        return http.Response('Error', 500);
      }));
    });

    test('getLastSeenText formats correctly', () {
      final now = DateTime(2026, 7, 12, 12, 0, 0);

      // Null case
      expect(VolumeRepository.getLastSeenText(null, now: now), 'Keine Verbindungshistorie');

      // Seconds cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(seconds: 5)), now: now), 'Gerade eben aktiv');
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(seconds: 45)), now: now), 'Vor 45 Sek. aktiv');

      // Minutes cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(minutes: 5)), now: now), 'Vor 5 Min. aktiv');

      // Hours cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(hours: 3)), now: now), 'Vor 3 Std. aktiv');

      // Days cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(days: 2)), now: now), 'Vor 2 Tagen aktiv');
    });
  });
}
