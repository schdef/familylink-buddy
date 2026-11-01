import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/bedtime/bedtime_schedule.dart';
import 'package:parent_app/bedtime/bedtime_repository.dart';
import 'package:parent_app/updater/p2p_updater_service.dart';

void main() {
  group('BedtimeSchedule Model Tests', () {
    test('Default values are correct', () {
      const schedule = BedtimeSchedule();
      expect(schedule.isEnabled, isFalse);
      expect(schedule.bedtimeHour, 20);
      expect(schedule.bedtimeMinute, 30);
      expect(schedule.wakeupHour, 6);
      expect(schedule.wakeupMinute, 45);
      expect(schedule.activeDays, [1, 2, 3, 4, 5, 6, 7]);
      expect(schedule.isCurrentlyBlocked, isFalse);
      expect(schedule.bedtimeFormatted, '20:30');
      expect(schedule.wakeupFormatted, '06:45');
      expect(schedule.bedtimeFormattedWithUnit, '20:30 Uhr');
      expect(schedule.wakeupFormattedWithUnit, '06:45 Uhr');
    });

    test('toJson and fromJson round-trip', () {
      const original = BedtimeSchedule(
        isEnabled: true,
        bedtimeHour: 21,
        bedtimeMinute: 15,
        wakeupHour: 7,
        wakeupMinute: 0,
        activeDays: [1, 2, 3, 4, 7],
        isCurrentlyBlocked: true,
      );

      final json = original.toJson();
      expect(json['isEnabled'], isTrue);
      expect(json['bedtimeHour'], 21);
      expect(json['bedtimeMinute'], 15);
      expect(json['wakeupHour'], 7);
      expect(json['wakeupMinute'], 0);
      expect(json['activeDays'], [1, 2, 3, 4, 7]);
      expect(json['isCurrentlyBlocked'], isTrue);

      final reconstructed = BedtimeSchedule.fromJson(json);
      expect(reconstructed, equals(original));
      expect(reconstructed.bedtimeFormatted, '21:15');
      expect(reconstructed.wakeupFormatted, '07:00');
    });

    test('fromJson handles nulls and defaults gracefully', () {
      final json = <String, dynamic>{};
      final schedule = BedtimeSchedule.fromJson(json);

      expect(schedule.isEnabled, isFalse);
      expect(schedule.bedtimeHour, 20);
      expect(schedule.bedtimeMinute, 30);
      expect(schedule.wakeupHour, 6);
      expect(schedule.wakeupMinute, 45);
      expect(schedule.activeDays, [1, 2, 3, 4, 5, 6, 7]);
      expect(schedule.isCurrentlyBlocked, isFalse);
    });

    test('copyWith modifies only targeted fields', () {
      const initial = BedtimeSchedule();
      final modified = initial.copyWith(
        isEnabled: true,
        bedtimeHour: 22,
        activeDays: [5, 6],
      );

      expect(modified.isEnabled, isTrue);
      expect(modified.bedtimeHour, 22);
      expect(modified.bedtimeMinute, 30); // unchanged
      expect(modified.wakeupHour, 6); // unchanged
      expect(modified.activeDays, [5, 6]);
      expect(modified.isCurrentlyBlocked, isFalse); // unchanged
    });

    test('Helper formatting and day checking', () {
      const schedule = BedtimeSchedule(
        bedtimeHour: 8,
        bedtimeMinute: 5,
        wakeupHour: 9,
        wakeupMinute: 0,
        activeDays: [1, 3, 5],
      );

      expect(schedule.bedtimeFormatted, '08:05');
      expect(schedule.wakeupFormatted, '09:00');
      expect(schedule.isDayActive(1), isTrue);
      expect(schedule.isDayActive(2), isFalse);
      expect(schedule.isDayActive(3), isTrue);

      // Presets activeDaysSummary
      expect(const BedtimeSchedule(activeDays: [1, 2, 3, 4, 5, 6, 7]).activeDaysSummary, 'Jeden Tag');
      expect(const BedtimeSchedule(activeDays: [7, 1, 2, 3, 4]).activeDaysSummary, 'Schultage (So–Do)');
      expect(const BedtimeSchedule(activeDays: [1, 2, 3, 4, 5]).activeDaysSummary, 'Montag – Freitag');
      expect(const BedtimeSchedule(activeDays: [5, 6]).activeDaysSummary, 'Wochenende (Fr–Sa)');
      expect(const BedtimeSchedule(activeDays: []).activeDaysSummary, 'Keine Tage');
    });
  });

  group('BedtimeRepository Tests', () {
    test('saveSchedule executes direct REST API call when localIpAddress is provided', () async {
      final repo = BedtimeRepository();
      const newSchedule = BedtimeSchedule(
        isEnabled: true,
        bedtimeHour: 21,
        bedtimeMinute: 0,
        activeDays: [1, 2, 3, 4, 5],
      );

      bool endpointCalled = false;
      await http.runWithClient(() async {
        final result = await repo.saveSchedule(
          'dummy_child_token',
          newSchedule,
          localIpAddress: '192.168.1.150',
        );

        expect(result, isTrue);
        expect(repo.schedule.isEnabled, isTrue);
        expect(repo.schedule.bedtimeHour, 21);
      }, () => MockClient((request) async {
        if (request.url.toString() == 'http://192.168.1.150:8085/set_schedule') {
          endpointCalled = true;
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['isEnabled'], isTrue);
          expect(body['bedtimeHour'], 21);
          return http.Response(jsonEncode({'status': 'success'}), 200);
        }
        return http.Response('Not Found', 404);
      }));

      expect(endpointCalled, isTrue);
    });

    test('toggleManualBlock executes direct REST API call when localIpAddress is provided', () async {
      final repo = BedtimeRepository();

      bool endpointCalled = false;
      await http.runWithClient(() async {
        final result = await repo.toggleManualBlock(
          'dummy_child_token',
          true,
          localIpAddress: '192.168.1.150',
        );

        expect(result, isTrue);
        expect(repo.schedule.isCurrentlyBlocked, isTrue);
      }, () => MockClient((request) async {
        if (request.url.toString() == 'http://192.168.1.150:8085/toggle_wifi?block=true') {
          endpointCalled = true;
          expect(request.method, 'POST');
          return http.Response(jsonEncode({'status': 'success', 'block': true}), 200);
        }
        return http.Response('Not Found', 404);
      }));

      expect(endpointCalled, isTrue);
    });
  });

  group('P2PUpdaterService Tests', () {
    test('pushUpdateToChild throws if APK file does not exist', () async {
      final updater = P2PUpdaterService();
      expect(
        () => updater.pushUpdateToChild(
          childLocalIp: '192.168.1.150',
          apkFilePath: '/non/existent/file.apk',
          onProgress: (_) {},
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('pushUpdateToChild streams bytes with progress tracking', () async {
      // Create a temporary file with dummy content
      final tempFile = File('${Directory.systemTemp.path}/test_upload.apk');
      final dummyBytes = List<int>.generate(1024 * 10, (i) => i % 256); // 10 KB
      await tempFile.writeAsBytes(dummyBytes);

      try {
        final List<double> progressLog = [];
        final mockClient = MockClient((request) async {
          expect(request.url.toString(), 'http://192.168.1.150:8085/upload_update');
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'], 'application/vnd.android.package-archive');
          final bytes = await request.bodyBytes;
          expect(bytes.length, dummyBytes.length);
          return http.Response('{"status":"success"}', 200);
        });

        final updater = P2PUpdaterService(client: mockClient);
        final success = await updater.pushUpdateToChild(
          childLocalIp: '192.168.1.150',
          apkFilePath: tempFile.path,
          onProgress: (p) {
            progressLog.add(p);
          },
        );

        expect(success, isTrue);
        expect(progressLog, isNotEmpty);
        expect(progressLog.first, 0.0);
        expect(progressLog.last, 1.0);
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    });
  });
}
