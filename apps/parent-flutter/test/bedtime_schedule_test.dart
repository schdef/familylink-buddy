import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/bedtime/bedtime_schedule.dart';
import 'package:parent_app/bedtime/bedtime_repository.dart';
import 'package:parent_app/bedtime/bedtime_schedule_screen.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/volume/volume_repository.dart';
import 'package:parent_app/l10n/app_strings.dart';
import 'package:parent_app/updater/p2p_updater_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.manualLocale = const Locale('de');
  });

  tearDown(() {
    AppStrings.manualLocale = null;
  });

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
      expect(const BedtimeSchedule(activeDays: [1, 2, 3, 4, 5]).activeDaysSummary, 'Schultage (Mo–Fr)');
      expect(const BedtimeSchedule(activeDays: [5, 6]).activeDaysSummary, 'Wochenende (Fr–Sa)');
      expect(const BedtimeSchedule(activeDays: []).activeDaysSummary, 'Keine Tage');
    });

    test('toJson and fromJson round-trip with Monday-Friday school days', () {
      const original = BedtimeSchedule(
        isEnabled: true,
        bedtimeHour: 20,
        bedtimeMinute: 0,
        activeDays: [1, 2, 3, 4, 5],
      );
      final json = original.toJson();
      expect(json['activeDays'], [1, 2, 3, 4, 5]);
      final reconstructed = BedtimeSchedule.fromJson(json);
      expect(reconstructed.activeDays, [1, 2, 3, 4, 5]);
      expect(reconstructed, equals(original));
    });

    test('activeDaysSummary and localizedActiveDaysSummary in German and English', () {
      const schoolDaysSchedule = BedtimeSchedule(activeDays: [1, 2, 3, 4, 5]);
      const everyDaySchedule = BedtimeSchedule(activeDays: [1, 2, 3, 4, 5, 6, 7]);
      const weekendSchedule = BedtimeSchedule(activeDays: [6, 7]);
      const customSchedule = BedtimeSchedule(activeDays: [1, 3, 5]);
      const emptySchedule = BedtimeSchedule(activeDays: []);

      final en = AppStrings.getStrings('en');
      final de = AppStrings.getStrings('de');

      // German verification
      expect(schoolDaysSchedule.localizedActiveDaysSummary(de), 'Schultage (Mo–Fr)');
      expect(everyDaySchedule.localizedActiveDaysSummary(de), 'Jeden Tag');
      expect(weekendSchedule.localizedActiveDaysSummary(de), 'Wochenende (Sa–So)');
      expect(customSchedule.localizedActiveDaysSummary(de), 'Mo, Mi, Fr');
      expect(emptySchedule.localizedActiveDaysSummary(de), 'Keine Tage');

      // English verification
      expect(schoolDaysSchedule.localizedActiveDaysSummary(en), 'School days (Mon–Fri)');
      expect(everyDaySchedule.localizedActiveDaysSummary(en), 'Every day');
      expect(weekendSchedule.localizedActiveDaysSummary(en), 'Weekend (Sat–Sun)');
      expect(customSchedule.localizedActiveDaysSummary(en), 'Mo, We, Fr');
      expect(emptySchedule.localizedActiveDaysSummary(en), 'No days');

      // Test activeDaysSummary getter with manualLocale
      AppStrings.manualLocale = const Locale('de');
      expect(schoolDaysSchedule.activeDaysSummary, 'Schultage (Mo–Fr)');
      expect(everyDaySchedule.activeDaysSummary, 'Jeden Tag');

      AppStrings.manualLocale = const Locale('en');
      expect(schoolDaysSchedule.activeDaysSummary, 'School days (Mon–Fri)');
      expect(everyDaySchedule.activeDaysSummary, 'Every day');

      // Reset to default de for following tests
      AppStrings.manualLocale = const Locale('de');
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

    test('fetchSchedule updates schedule from mock HTTP response with nested schedule object', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.150:8085/get_schedule');
        expect(request.method, 'GET');
        expect(request.headers['X-Buddy-Token'], 'test_token_123');

        return http.Response(
          jsonEncode({
            'status': 'success',
            'schedule': {
              'isEnabled': true,
              'bedtimeHour': 21,
              'bedtimeMinute': 45,
              'wakeupHour': 7,
              'wakeupMinute': 15,
              'activeDays': [1, 2, 3, 4, 5],
              'isCurrentlyBlocked': false,
            },
          }),
          200,
        );
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      final success = await repo.fetchSchedule('test_token_123', localIpAddress: '192.168.1.150');

      expect(success, isTrue);
      expect(repo.schedule.isEnabled, isTrue);
      expect(repo.schedule.bedtimeHour, 21);
      expect(repo.schedule.bedtimeMinute, 45);
      expect(repo.schedule.wakeupHour, 7);
      expect(repo.schedule.wakeupMinute, 15);
      expect(repo.schedule.activeDays, [1, 2, 3, 4, 5]);

      // Verify it was cached in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(BedtimeRepository.cacheKey('test_token_123'));
      expect(cachedJson, isNotNull);
      final decoded = jsonDecode(cachedJson!) as Map<String, dynamic>;
      expect(decoded['isEnabled'], isTrue);
      expect(decoded['bedtimeHour'], 21);
    });

    test('fetchSchedule handles flat JSON response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'isEnabled': true,
            'bedtimeHour': 22,
            'bedtimeMinute': 0,
            'wakeupHour': 8,
            'wakeupMinute': 30,
            'activeDays': [6, 7],
            'isCurrentlyBlocked': true,
          }),
          200,
        );
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      final success = await repo.fetchSchedule('test_flat_token', localIpAddress: '192.168.1.150');

      expect(success, isTrue);
      expect(repo.schedule.isEnabled, isTrue);
      expect(repo.schedule.bedtimeHour, 22);
      expect(repo.schedule.wakeupHour, 8);
      expect(repo.schedule.isCurrentlyBlocked, isTrue);
    });

    test('fetchSchedule returns false and keeps state on error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      const initial = BedtimeSchedule(isEnabled: false, bedtimeHour: 20);
      repo.schedule = initial;

      final success = await repo.fetchSchedule('token_err', localIpAddress: '192.168.1.150');
      expect(success, isFalse);
      expect(repo.schedule.isEnabled, isFalse);
      expect(repo.schedule.bedtimeHour, 20);
    });

    test('loadCache and saveCache persist and restore schedule correctly', () async {
      final scheduleToCache = const BedtimeSchedule(
        isEnabled: true,
        bedtimeHour: 22,
        bedtimeMinute: 10,
        wakeupHour: 7,
        wakeupMinute: 20,
        activeDays: [1, 2, 3],
        isCurrentlyBlocked: false,
      );

      SharedPreferences.setMockInitialValues({
        BedtimeRepository.cacheKey('cached_child_1'): jsonEncode(scheduleToCache.toJson()),
      });

      final repo = BedtimeRepository();
      expect(repo.schedule.isEnabled, isFalse); // default before loading cache

      await repo.loadCache('cached_child_1');
      expect(repo.schedule.isEnabled, isTrue);
      expect(repo.schedule.bedtimeHour, 22);
      expect(repo.schedule.bedtimeMinute, 10);
      expect(repo.schedule.activeDays, [1, 2, 3]);

      // Modify and save cache
      final updatedSchedule = repo.schedule.copyWith(bedtimeHour: 23, isEnabled: false);
      repo.schedule = updatedSchedule;
      await repo.saveCache('cached_child_1');

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(BedtimeRepository.cacheKey('cached_child_1'));
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['bedtimeHour'], 23);
      expect(decoded['isEnabled'], isFalse);
    });

    test('subscribeToDevice loads cache, triggers fetchSchedule, and starts periodic timer', () async {
      final cachedSchedule = const BedtimeSchedule(
        isEnabled: true,
        bedtimeHour: 21,
        bedtimeMinute: 30,
      );

      SharedPreferences.setMockInitialValues({
        BedtimeRepository.cacheKey('sub_token'): jsonEncode(cachedSchedule.toJson()),
      });

      int fetchCount = 0;
      final mockClient = MockClient((request) async {
        fetchCount++;
        return http.Response(
          jsonEncode({
            'schedule': {
              'isEnabled': true,
              'bedtimeHour': 22,
              'bedtimeMinute': 0,
            },
          }),
          200,
        );
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      await repo.subscribeToDevice('sub_token', localIpAddress: '192.168.1.50');

      // Cache is loaded immediately
      expect(repo.pollingTimer, isNotNull);
      expect(repo.pollingTimer!.isActive, isTrue);

      // Let async fetch finish
      await Future.delayed(const Duration(milliseconds: 50));
      expect(fetchCount, greaterThanOrEqualTo(1));
      expect(repo.schedule.bedtimeHour, 22);

      // Stop polling cancels timer
      repo.stopPolling();
      expect(repo.pollingTimer, isNull);
    });

    test('dispose cancels pollingTimer and suppresses notifyListeners', () async {
      final repo = BedtimeRepository();
      await repo.subscribeToDevice('dummy_tok');
      expect(repo.pollingTimer, isNotNull);

      bool notifiedAfterDispose = false;
      repo.addListener(() {
        notifiedAfterDispose = true;
      });

      repo.dispose();
      expect(repo.pollingTimer, isNull);

      // Calling notifyListeners directly should be safely ignored
      repo.notifyListeners();
      expect(notifiedAfterDispose, isFalse);
    });
  });

  group('BedtimeScheduleScreen Widget Tests', () {
    testWidgets('Renders screen, starts polling, and dispose stops polling', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'schedule': const BedtimeSchedule(isEnabled: true, bedtimeHour: 20, bedtimeMinute: 30).toJson(),
          }),
          200,
        );
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      final testDevice = PairedDevice(
        id: 'tablet-1',
        name: 'Kind-Tablet',
        fcmToken: 'token_tablet_1',
        localIpAddress: '192.168.1.180',
        port: 8085,
        lastSeen: DateTime.now(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BedtimeRepository>.value(value: repo),
            ChangeNotifierProvider<VolumeRepository>(create: (_) => VolumeRepository()),
          ],
          child: MaterialApp(
            home: BedtimeScheduleScreen(
              device: testDevice,
              localIpAddress: '192.168.1.180',
            ),
          ),
        ),
      );

      // Trigger post frame callbacks
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('WLAN-Nachtruhe'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(repo.pollingTimer, isNotNull);
      expect(repo.pollingTimer!.isActive, isTrue);

      // Unmount the screen to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Done')),
        ),
      );
      await tester.pump();

      expect(repo.pollingTimer, isNull);
    });

    testWidgets('Pull to refresh calls fetchSchedule', (WidgetTester tester) async {
      int getCalls = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/get_schedule') {
          getCalls++;
        }
        return http.Response(
          jsonEncode({
            'schedule': const BedtimeSchedule(isEnabled: true, bedtimeHour: 21).toJson(),
          }),
          200,
        );
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      final testDevice = PairedDevice(
        id: 'tablet-2',
        name: 'Kind-Tablet 2',
        fcmToken: 'token_tablet_2',
        localIpAddress: '192.168.1.181',
        port: 8085,
        lastSeen: DateTime.now(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BedtimeRepository>.value(value: repo),
            ChangeNotifierProvider<VolumeRepository>(create: (_) => VolumeRepository()),
          ],
          child: MaterialApp(
            home: BedtimeScheduleScreen(
              device: testDevice,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final initialCalls = getCalls;

      // Trigger pull to refresh
      await tester.fling(find.byType(SingleChildScrollView), const Offset(0.0, 300.0), 1000.0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(getCalls, greaterThan(initialCalls));
      repo.stopPolling();
    });

    testWidgets('Tapping School Days and Every Day preset buttons updates schedule', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      BedtimeSchedule? savedSchedule;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/get_schedule') {
          return http.Response(
            jsonEncode({
              'schedule': const BedtimeSchedule(
                isEnabled: true,
                bedtimeHour: 20,
                bedtimeMinute: 30,
                activeDays: [1, 2, 3, 4, 5, 6, 7],
              ).toJson(),
            }),
            200,
          );
        }
        if (request.url.path == '/set_schedule') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          savedSchedule = BedtimeSchedule.fromJson(body);
          return http.Response(jsonEncode({'status': 'success'}), 200);
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final repo = BedtimeRepository(httpClient: mockClient);
      final testDevice = PairedDevice(
        id: 'tablet-preset-test',
        name: 'Kind-Tablet',
        fcmToken: 'token_tablet_preset_test',
        localIpAddress: '192.168.1.180',
        port: 8085,
        lastSeen: DateTime.now(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BedtimeRepository>.value(value: repo),
            ChangeNotifierProvider<VolumeRepository>(create: (_) => VolumeRepository()),
          ],
          child: MaterialApp(
            home: BedtimeScheduleScreen(
              device: testDevice,
              localIpAddress: '192.168.1.180',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find and tap School Days preset ('Schultage (Mo–Fr)')
      final schoolDaysButton = find.text('Schultage (Mo–Fr)');
      expect(schoolDaysButton, findsOneWidget);
      await tester.tap(schoolDaysButton);
      await tester.pumpAndSettle();

      expect(savedSchedule, isNotNull);
      expect(savedSchedule!.activeDays, [1, 2, 3, 4, 5]);

      // Find and tap Every Day preset ('Jeden Tag')
      final everyDayButton = find.text('Jeden Tag');
      expect(everyDayButton, findsOneWidget);
      await tester.tap(everyDayButton);
      await tester.pumpAndSettle();

      expect(savedSchedule!.activeDays, [1, 2, 3, 4, 5, 6, 7]);
      repo.stopPolling();
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
          final bytes = request.bodyBytes;
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
