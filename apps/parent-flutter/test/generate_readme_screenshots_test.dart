import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parent_app/app_limits/app_limits_model.dart';
import 'package:parent_app/app_limits/app_limits_repository.dart';
import 'package:parent_app/app_limits/app_limits_screen.dart';
import 'package:parent_app/bedtime/bedtime_repository.dart';
import 'package:parent_app/bedtime/bedtime_schedule.dart';
import 'package:parent_app/bedtime/bedtime_schedule_screen.dart';
import 'package:parent_app/comms/calls_screen.dart';
import 'package:parent_app/comms/chats_screen.dart';
import 'package:parent_app/comms/comms_models.dart';
import 'package:parent_app/comms/comms_repository.dart';
import 'package:parent_app/l10n/app_strings.dart';
import 'package:parent_app/pairing/lan_discovery_service.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/pairing/pairing_screen.dart';
import 'package:parent_app/screenshot/screenshot_model.dart';
import 'package:parent_app/screenshot/screenshot_repository.dart';
import 'package:parent_app/screenshot/screenshot_screen.dart';
import 'package:parent_app/volume/volume_control_screen.dart';
import 'package:parent_app/volume/volume_repository.dart';

Future<void> loadRealFonts() async {
  const fontDir = '/home/stefanheintz/flutter/bin/cache/artifacts/material_fonts';

  final robotoLoader = FontLoader('Roboto');
  robotoLoader.addFont(File('$fontDir/Roboto-Regular.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  robotoLoader.addFont(File('$fontDir/Roboto-Bold.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  robotoLoader.addFont(File('$fontDir/Roboto-Medium.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await robotoLoader.load();

  final iconLoader = FontLoader('MaterialIcons');
  iconLoader.addFont(File('$fontDir/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await iconLoader.load();
}

class TolerantGoldenComparator extends LocalFileComparator {
  final double tolerance;

  TolerantGoldenComparator(super.testFile, {this.tolerance = 0.01});

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (!result.passed && result.diffPercent <= tolerance) {
      debugPrint(
        'A difference of ${(result.diffPercent * 100).toStringAsFixed(2)}% was found, acceptable within tolerance.',
      );
      return true;
    }
    if (!result.passed) {
      final String error = await generateFailureOutput(result, golden, basedir);
      throw FlutterError(error);
    }
    return result.passed;
  }
}

ThemeData get appDarkTheme => ThemeData(
  fontFamily: 'Roboto',
  brightness: Brightness.dark,
  primaryColor: const Color(0xFF6366F1),
  scaffoldBackgroundColor: const Color(0xFF0F172A),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF6366F1),
    secondary: Color(0xFF10B981),
    surface: Color(0xFF1E293B),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF1E293B),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 0,
  ),
  useMaterial3: true,
);

final testDevice = PairedDevice(
  id: 'tablet_emma',
  name: "Emma's Tablet",
  token: 'sec_emma_token_123',
  localIpAddress: '192.168.1.150',
  port: 8085,
  lastSeen: DateTime(2026, 11, 21, 12, 0),
);

class TestCommsRepository extends CommsRepository {
  TestCommsRepository({super.httpClient});

  final DateTime _fixedLastSynced = DateTime(2026, 11, 15, 12, 0);

  @override
  DateTime? get lastSyncedAt => _fixedLastSynced;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final currentComparator = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = TolerantGoldenComparator(
      currentComparator.basedir.resolve('generate_readme_screenshots_test.dart'),
      tolerance: 0.01,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.manualLocale = const Locale('en');
  });

  tearDown(() {
    AppStrings.manualLocale = null;
  });

  group('Generate README Screenshots', () {
    // 1. Parent Dashboard (VolumeControlScreen)
    testWidgets('parent_dashboard', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final volMockClient = MockClient((request) async {
        if (request.url.path == '/volume_report') {
          return http.Response(
            jsonEncode({
              'mediaVolume': 10,
              'ringtoneVolume': 7,
              'alarmVolume': 12,
              'maxMediaVolume': 15,
              'maxRingtoneVolume': 15,
              'maxAlarmVolume': 15,
              'isMuted': false,
              'isMusicActive': true,
              'mediaTitle': 'The Fox (What Does The Fox Say?)',
              'mediaArtist': 'Ylvis',
              'mediaPackage': 'com.spotify.music',
              'timestamp': DateTime(2026, 11, 21, 12, 0).millisecondsSinceEpoch,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final volRepo = VolumeRepository(httpClient: volMockClient);
      volRepo.localIpAddress = testDevice.localIpAddress;
      volRepo.volumeStateForTesting = VolumeState(
        mediaVolume: 10,
        ringtoneVolume: 7,
        alarmVolume: 12,
        maxMediaVolume: 15,
        maxRingtoneVolume: 15,
        maxAlarmVolume: 15,
        isMuted: false,
        isMusicActive: true,
        mediaTitle: 'The Fox (What Does The Fox Say?)',
        mediaArtist: 'Ylvis',
        mediaPackage: 'com.spotify.music',
        timestamp: DateTime(2026, 11, 21, 12, 0),
      );

      final pairingRepo = PairingRepository();
      await pairingRepo.savePairedDevice(testDevice);

      final lanDiscoveryService = LanDiscoveryService(client: volMockClient);
      final appLimitsRepo = AppLimitsRepository(httpClient: volMockClient);
      final bedtimeRepo = BedtimeRepository(httpClient: volMockClient);
      final screenshotRepo = ScreenshotRepository(httpClient: volMockClient);
      final commsRepo = CommsRepository(httpClient: volMockClient);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VolumeRepository>.value(value: volRepo),
            Provider<PairingRepository>.value(value: pairingRepo),
            Provider<LanDiscoveryService>.value(value: lanDiscoveryService),
            ChangeNotifierProvider<AppLimitsRepository>.value(value: appLimitsRepo),
            ChangeNotifierProvider<BedtimeRepository>.value(value: bedtimeRepo),
            ChangeNotifierProvider<ScreenshotRepository>.value(value: screenshotRepo),
            ChangeNotifierProvider<CommsRepository>.value(value: commsRepo),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: VolumeControlScreen(device: testDevice),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_dashboard.png'),
      );

      volRepo.stopPolling();
    });

    // 2. Communication & Calls Monitoring Screen (CallsScreen)
    testWidgets('parent_calls_monitoring', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixedDate = DateTime(2026, 11, 15);
      final sampleCalls = [
        CallRecord(
          id: 'call_1',
          phoneNumber: '+1 (555) 234-5678',
          contactName: 'Mom',
          callType: CallType.incoming,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 11, 45).millisecondsSinceEpoch,
          durationSeconds: 252, // 4m 12s
        ),
        CallRecord(
          id: 'call_2',
          phoneNumber: '+1 (555) 876-5432',
          contactName: 'Dad',
          callType: CallType.outgoing,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 10, 15).millisecondsSinceEpoch,
          durationSeconds: 165, // 2m 45s
        ),
        CallRecord(
          id: 'call_3',
          phoneNumber: '+1 (555) 345-6789',
          contactName: 'Grandma Helen',
          callType: CallType.incoming,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 9, 0).millisecondsSinceEpoch,
          durationSeconds: 490, // 8m 10s
        ),
        CallRecord(
          id: 'call_4',
          phoneNumber: '+1 (555) 999-0000',
          contactName: null,
          callType: CallType.missed,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day - 1, 16, 20).millisecondsSinceEpoch,
          durationSeconds: 0,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_calls_${testDevice.id}',
        jsonEncode(sampleCalls.map((c) => c.toJson()).toList()),
      );
      await prefs.setInt(
        'comms_last_synced_${testDevice.id}',
        DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 12, 0).millisecondsSinceEpoch,
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/call_logs') {
          return http.Response(
            jsonEncode({'calls': sampleCalls.map((c) => c.toJson()).toList()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/chat_logs') {
          return http.Response(
            jsonEncode({'chats': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final commsRepo = TestCommsRepository(httpClient: mockClient);
      await commsRepo.loadCache(testDevice.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<CommsRepository>.value(
          value: commsRepo,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: CallsScreen(device: testDevice),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_calls_monitoring.png'),
      );
    });

    // 3. WhatsApp & SMS Messages Monitoring Screen (ChatsScreen)
    testWidgets('parent_chats_monitoring', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixedDate = DateTime(2026, 11, 15);
      final sampleChats = [
        ChatMessageRecord(
          id: 'chat_1',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'School Class 4B',
          text: "Don't forget to bring your art project tomorrow! 🎨",
          isOutgoing: false,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 11, 30).millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'chat_2',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Grandma Helen',
          text: 'Have fun at school today, my dear! ❤️',
          isOutgoing: false,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 10, 15).millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'chat_3',
          appPackage: 'com.google.android.apps.messaging',
          appName: 'Messages',
          senderOrChat: 'Soccer Club',
          text: 'Training starts at 16:30 at field 2 today.',
          isOutgoing: false,
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 8, 45).millisecondsSinceEpoch,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_chats_${testDevice.id}',
        jsonEncode(sampleChats.map((c) => c.toJson()).toList()),
      );
      await prefs.setInt(
        'comms_last_synced_${testDevice.id}',
        DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 12, 0).millisecondsSinceEpoch,
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/call_logs') {
          return http.Response(jsonEncode({'calls': []}), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/chat_logs') {
          return http.Response(
            jsonEncode({'chats': sampleChats.map((c) => c.toJson()).toList()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final commsRepo = TestCommsRepository(httpClient: mockClient);
      await commsRepo.loadCache(testDevice.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<CommsRepository>.value(
          value: commsRepo,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: ChatsScreen(device: testDevice),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_chats_monitoring.png'),
      );
    });

    // 4. App Limits & Categories Screen (AppLimitsScreen)
    testWidgets('parent_app_limits', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final categories = [
        const AppCategoryRule(
          id: 'cat-games',
          name: 'Games & Entertainment',
          packageNames: [
            'com.roblox.client',
            'com.mojang.minecraftpe',
            'com.supercell.brawlstars',
          ],
          dailyLimitMinutes: 60,
          bonusMinutes: 15,
          usedMinutes: 45,
        ),
        const AppCategoryRule(
          id: 'cat-video',
          name: 'Video & Streaming',
          packageNames: [
            'com.google.android.apps.youtube.kids',
            'com.netflix.ninja',
            'com.disney.disneyplus',
          ],
          dailyLimitMinutes: 45,
          bonusMinutes: 0,
          usedMinutes: 30,
        ),
        const AppCategoryRule(
          id: 'cat-social',
          name: 'Social Media',
          packageNames: [
            'com.zhiliaoapp.musically',
          ],
          dailyLimitMinutes: 30,
          bonusMinutes: 0,
          usedMinutes: 15,
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/app_limits') {
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'categories': categories.map((c) => c.toJson()).toList(),
              'blacklist': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final appLimitsRepo = AppLimitsRepository(httpClient: mockClient);
      appLimitsRepo.state = AppLimitsState(
        categories: categories,
        installedApps: AppLimitsRepository.defaultInstalledApps,
        blacklistedPackages: const [],
      );

      final volRepo = VolumeRepository();
      volRepo.localIpAddress = testDevice.localIpAddress;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppLimitsRepository>.value(value: appLimitsRepo),
            ChangeNotifierProvider<VolumeRepository>.value(value: volRepo),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: AppLimitsScreen(device: testDevice),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Categories tab to display the 3 active categories with limits and bonus buttons
      await tester.tap(find.byKey(const ValueKey('tab_categories')));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_app_limits.png'),
      );

      appLimitsRepo.stopPolling();
    });

    // 5. Bedtime Schedule & Wi-Fi Automation Screen (BedtimeScheduleScreen)
    testWidgets('parent_bedtime', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const schedule = BedtimeSchedule(
        isEnabled: true,
        bedtimeHour: 20,
        bedtimeMinute: 30,
        wakeupHour: 7,
        wakeupMinute: 0,
        activeDays: [1, 2, 3, 4, 5],
        isCurrentlyBlocked: false,
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/bedtime_schedule') {
          return http.Response(
            jsonEncode({'schedule': schedule.toJson()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final bedtimeRepo = BedtimeRepository(httpClient: mockClient);
      bedtimeRepo.schedule = schedule;

      final volRepo = VolumeRepository();
      volRepo.localIpAddress = testDevice.localIpAddress;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BedtimeRepository>.value(value: bedtimeRepo),
            ChangeNotifierProvider<VolumeRepository>.value(value: volRepo),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: BedtimeScheduleScreen(device: testDevice),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_bedtime.png'),
      );

      bedtimeRepo.stopPolling();
    });

    // 6. Silent Camera & Remote Screenshots (ScreenshotScreen)
    testWidgets('parent_camera_screenshots', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const samplePngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mNk+M9QzwAEjAwMDAwAFAkCA/s3LpYAAAAASUVORK5CYII=';

      final fixedDate = DateTime(2026, 11, 15);
      final sampleScreenshots = [
        ScreenshotItem(
          id: 'shot_1',
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 15, 30),
          base64Image: samplePngBase64,
          deviceModel: 'Samsung Galaxy Tab A9',
          foregroundApp: 'YouTube Kids',
          foregroundPackage: 'com.google.android.apps.youtube.kids',
        ),
        ScreenshotItem(
          id: 'shot_2',
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 14, 15),
          base64Image: samplePngBase64,
          deviceModel: 'Samsung Galaxy Tab A9',
          foregroundApp: 'Roblox',
          foregroundPackage: 'com.roblox.client',
        ),
        ScreenshotItem(
          id: 'shot_3',
          timestamp: DateTime(fixedDate.year, fixedDate.month, fixedDate.day, 11, 0),
          base64Image: samplePngBase64,
          deviceModel: 'Samsung Galaxy Tab A9',
          foregroundApp: 'Minecraft',
          foregroundPackage: 'com.mojang.minecraftpe',
        ),
      ];

      final mockClient = MockClient((request) async {
        return http.Response('{"status":"ok"}', 200);
      });

      final screenshotRepo = ScreenshotRepository(httpClient: mockClient);
      screenshotRepo.setHistoryForTesting(sampleScreenshots);

      final volRepo = VolumeRepository();
      volRepo.localIpAddress = testDevice.localIpAddress;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ScreenshotRepository>.value(value: screenshotRepo),
            ChangeNotifierProvider<VolumeRepository>.value(value: volRepo),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: ScreenshotScreen(device: testDevice),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_camera_screenshots.png'),
      );
    });

    // 7. QR Code Pairing Screen (PairingScreen)
    testWidgets('parent_pairing', (tester) async {
      await tester.runAsync(() async => await loadRealFonts());
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockClient = MockClient((request) async {
        return http.Response('{"status":"ok"}', 200);
      });

      final volRepo = VolumeRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VolumeRepository>.value(value: volRepo),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            theme: appDarkTheme,
            home: PairingScreen(httpClient: mockClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/parent_pairing.png'),
      );
    });
  });
}
