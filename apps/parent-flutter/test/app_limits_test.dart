// ignore_for_file: subtype_of_sealed_class
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:parent_app/app_limits/app_limits_model.dart';
import 'package:parent_app/app_limits/app_limits_repository.dart';
import 'package:parent_app/app_limits/app_limits_screen.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/volume/volume_control_screen.dart';
import 'package:parent_app/volume/volume_repository.dart';
import 'package:parent_app/l10n/app_strings.dart';

void main() {
  setUp(() {
    AppStrings.manualLocale = const Locale('de');
  });

  tearDown(() {
    AppStrings.manualLocale = null;
  });

  final testDevice = PairedDevice(
    name: 'Kind-Tablet',
    fcmToken: 'test-token-123',
    lastSeen: DateTime(2026, 11, 4, 12, 0),
  );

  group('InstalledAppInfo Model Tests', () {
    test('Constructs, serializes and deserializes', () {
      const app = InstalledAppInfo(
        packageName: 'com.google.android.apps.chromecast.app',
        appName: 'Google Home',
        iconBase64: 'base64icon',
      );

      final json = app.toJson();
      expect(json['packageName'], 'com.google.android.apps.chromecast.app');
      expect(json['appName'], 'Google Home');
      expect(json['iconBase64'], 'base64icon');

      final reconstructed = InstalledAppInfo.fromJson(json);
      expect(reconstructed, equals(app));
      expect(reconstructed.toString(), contains('Google Home'));
    });

    test('copyWith works correctly', () {
      const app = InstalledAppInfo(
        packageName: 'com.roblox.client',
        appName: 'Roblox',
      );

      final updated = app.copyWith(appName: 'Roblox Kids');
      expect(updated.packageName, 'com.roblox.client');
      expect(updated.appName, 'Roblox Kids');
    });

    test('fromJson handles alternate key names (pkg, name)', () {
      final json = {
        'pkg': 'com.supercell.brawlstars',
        'name': 'Brawl Stars',
      };
      final app = InstalledAppInfo.fromJson(json);
      expect(app.packageName, 'com.supercell.brawlstars');
      expect(app.appName, 'Brawl Stars');
    });
  });

  group('AppCategoryRule Model Tests', () {
    test('Calculates remaining minutes, progress, and limit reached', () {
      const rule = AppCategoryRule(
        id: 'cat-1',
        name: 'Spiele',
        packageNames: ['com.roblox.client'],
        dailyLimitMinutes: 60,
        bonusMinutes: 15, // Total allowed: 75
        usedMinutes: 30, // Remaining: 45
      );

      expect(rule.totalAllowedMinutes, 75);
      expect(rule.remainingMinutes, 45);
      expect(rule.isLimitReached, isFalse);
      expect(rule.usageProgress, closeTo(30 / 75, 0.001));
      expect(rule.dailyLimitFormatted, '1 Std.');
      expect(rule.remainingFormatted, '45 Min.');
      expect(rule.totalAllowedFormatted, '1 Std. 15 Min.');
    });

    test('Handles limit reached and overconsumption clamp', () {
      const rule = AppCategoryRule(
        id: 'cat-2',
        name: 'Videos',
        dailyLimitMinutes: 45,
        bonusMinutes: 0,
        usedMinutes: 60,
      );

      expect(rule.totalAllowedMinutes, 45);
      expect(rule.remainingMinutes, 0);
      expect(rule.isLimitReached, isTrue);
      expect(rule.usageProgress, 1.0);
    });

    test('formatMinutes produces expected human-readable strings', () {
      expect(AppCategoryRule.formatMinutes(0), '0 Min.');
      expect(AppCategoryRule.formatMinutes(15), '15 Min.');
      expect(AppCategoryRule.formatMinutes(60), '1 Std.');
      expect(AppCategoryRule.formatMinutes(90), '1 Std. 30 Min.');
      expect(AppCategoryRule.formatMinutes(120), '2 Std.');
    });

    test('toJson and fromJson round-trip', () {
      const rule = AppCategoryRule(
        id: 'cat-social',
        name: 'Social',
        packageNames: ['com.zhiliaoapp.musically'],
        dailyLimitMinutes: 30,
        bonusMinutes: 10,
        usedMinutes: 5,
        iconName: 'chat',
        colorHex: 0xFFEC4899,
      );

      final json = rule.toJson();
      final restored = AppCategoryRule.fromJson(json);
      expect(restored, equals(rule));
    });

    test('copyWith updates fields properly', () {
      const rule = AppCategoryRule(id: 'cat-1', name: 'Test', dailyLimitMinutes: 60);
      final updated = rule.copyWith(name: 'Updated', bonusMinutes: 15);
      expect(updated.id, 'cat-1');
      expect(updated.name, 'Updated');
      expect(updated.bonusMinutes, 15);
      expect(updated.dailyLimitMinutes, 60);
    });
  });

  group('AppLimitsState Model Tests', () {
    test('isBlacklisted, getCategoryForPackage, getAppName helpers', () {
      final state = AppLimitsState(
        blacklistedPackages: ['com.google.android.apps.chromecast.app'],
        categories: [
          const AppCategoryRule(
            id: 'c1',
            name: 'Spiele',
            packageNames: ['com.roblox.client'],
          ),
        ],
        installedApps: [
          const InstalledAppInfo(
            packageName: 'com.google.android.apps.chromecast.app',
            appName: 'Google Home',
          ),
          const InstalledAppInfo(
            packageName: 'com.roblox.client',
            appName: 'Roblox',
          ),
        ],
      );

      expect(state.isBlacklisted('com.google.android.apps.chromecast.app'), isTrue);
      expect(state.isBlacklisted('com.roblox.client'), isFalse);

      expect(state.getCategoryForPackage('com.roblox.client')?.name, 'Spiele');
      expect(state.getCategoryForPackage('com.unknown'), isNull);

      expect(state.getAppName('com.google.android.apps.chromecast.app'), 'Google Home');
      expect(state.getAppName('com.example.foobar'), 'Foobar');
    });

    test('toJson and fromJson round-trip', () {
      final now = DateTime(2026, 11, 4, 15, 0);
      final state = AppLimitsState(
        blacklistedPackages: ['com.test.app'],
        categories: [
          const AppCategoryRule(id: 'c1', name: 'Cat 1', packageNames: ['com.test.app']),
        ],
        installedApps: [
          const InstalledAppInfo(packageName: 'com.test.app', appName: 'Test App'),
        ],
        appUsages: {'com.test.app': 25},
        lastUpdated: now,
      );

      final json = state.toJson();
      final reconstructed = AppLimitsState.fromJson(json);
      expect(reconstructed.blacklistedPackages, equals(state.blacklistedPackages));
      expect(reconstructed.categories, equals(state.categories));
      expect(reconstructed.installedApps, equals(state.installedApps));
      expect(reconstructed.appUsages, equals(state.appUsages));
    });
  });

  group('AppLimitsRepository Direct LAN & Rule Tests', () {
    test('saveRules posts to http://localIpAddress:8085/set_app_rules with valid JSON', () async {
      bool endpointCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.toString() == 'http://192.168.1.150:8085/set_app_rules' &&
            request.method == 'POST') {
          endpointCalled = true;
          expect(request.headers['Content-Type'], 'application/json');
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          expect(decoded['blacklistedPackages'], contains('com.google.android.apps.chromecast.app'));
          expect(decoded['categories'], isA<List>());
          return http.Response(jsonEncode({'status': 'success'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final repo = AppLimitsRepository(httpClient: mockClient);
      repo.state = repo.state.copyWith(
        blacklistedPackages: ['com.google.android.apps.chromecast.app'],
      );

      final success = await repo.saveRules(
        testDevice.fcmToken,
        localIpAddress: '192.168.1.150',
      );

      expect(success, isTrue);
      expect(endpointCalled, isTrue);
    });

    test('toggleBlacklist updates state and triggers saveRules', () async {
      int postCount = 0;
      final mockClient = MockClient((request) async {
        postCount++;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final repo = AppLimitsRepository(httpClient: mockClient);
      expect(repo.state.isBlacklisted('com.roblox.client'), isFalse);

      // Block Roblox
      await repo.toggleBlacklist(
        testDevice.fcmToken,
        'com.roblox.client',
        true,
        localIpAddress: '192.168.1.120',
      );
      expect(repo.state.isBlacklisted('com.roblox.client'), isTrue);
      expect(postCount, 1);

      // Unblock Roblox
      await repo.toggleBlacklist(
        testDevice.fcmToken,
        'com.roblox.client',
        false,
        localIpAddress: '192.168.1.120',
      );
      expect(repo.state.isBlacklisted('com.roblox.client'), isFalse);
      expect(postCount, 2);
    });

    test('grantBonusMinutes adds bonus and posts update', () async {
      final mockClient = MockClient((request) async {
        final decoded = jsonDecode(request.body) as Map<String, dynamic>;
        final categories = decoded['categories'] as List;
        final games = categories.firstWhere((c) => c['id'] == 'cat-games');
        expect(games['bonusMinutes'], 15);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final repo = AppLimitsRepository(httpClient: mockClient);
      final initialBonus = repo.state.categories
          .firstWhere((c) => c.id == 'cat-games')
          .bonusMinutes;
      expect(initialBonus, 0);

      final success = await repo.grantBonusMinutes(
        testDevice.fcmToken,
        'cat-games',
        15,
        localIpAddress: '192.168.1.120',
      );

      expect(success, isTrue);
      final updatedBonus = repo.state.categories
          .firstWhere((c) => c.id == 'cat-games')
          .bonusMinutes;
      expect(updatedBonus, 15);
    });

    test('saveCategory creates new or modifies existing category', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final repo = AppLimitsRepository(httpClient: mockClient);
      const newCat = AppCategoryRule(
        id: 'cat-learning',
        name: 'Lernen',
        packageNames: ['com.duolingo'],
        dailyLimitMinutes: 40,
      );

      await repo.saveCategory(
        testDevice.fcmToken,
        newCat,
        localIpAddress: '192.168.1.120',
      );

      expect(repo.state.categories.any((c) => c.id == 'cat-learning'), isTrue);
      expect(
        repo.state.categories.firstWhere((c) => c.id == 'cat-learning').name,
        'Lernen',
      );
    });

    test('deleteCategory removes category by id', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final repo = AppLimitsRepository(httpClient: mockClient);
      expect(repo.state.categories.any((c) => c.id == 'cat-games'), isTrue);

      await repo.deleteCategory(
        testDevice.fcmToken,
        'cat-games',
        localIpAddress: '192.168.1.120',
      );

      expect(repo.state.categories.any((c) => c.id == 'cat-games'), isFalse);
    });

    test('handleSnapshotData parses Firestore payload and aggregates usage into categories', () {
      final repo = AppLimitsRepository();

      final firestoreDoc = {
        'blacklistedPackages': ['com.google.android.apps.chromecast.app'],
        'appCategories': [
          {
            'id': 'cat-gaming',
            'name': 'Gaming',
            'packageNames': ['com.roblox.client', 'com.mojang.minecraftpe'],
            'dailyLimitMinutes': 60,
            'bonusMinutes': 10,
          },
        ],
        'installedApps': [
          {'packageName': 'com.roblox.client', 'appName': 'Roblox'},
          {'packageName': 'com.mojang.minecraftpe', 'appName': 'Minecraft'},
        ],
        'appUsages': [
          {'pkg': 'com.roblox.client', 'used': 20},
          {'pkg': 'com.mojang.minecraftpe', 'used': 15},
        ],
      };

      repo.handleSnapshotData(firestoreDoc);

      expect(repo.state.blacklistedPackages, contains('com.google.android.apps.chromecast.app'));
      expect(repo.state.categories.length, 1);
      final gaming = repo.state.categories.first;
      expect(gaming.name, 'Gaming');
      expect(gaming.usedMinutes, 35); // 20 + 15
      expect(gaming.totalAllowedMinutes, 70); // 60 + 10
      expect(gaming.remainingMinutes, 35);
    });
  });

  group('AppLimitsScreen Widget Tests', () {
    final testMockClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    });

    Widget buildTestScreen({
      required AppLimitsRepository appLimitsRepo,
      VolumeRepository? volumeRepo,
      String? localIpAddress,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppLimitsRepository>.value(value: appLimitsRepo),
          ChangeNotifierProvider<VolumeRepository>.value(
            value: volumeRepo ?? VolumeRepository(),
          ),
        ],
        child: MaterialApp(
          home: AppLimitsScreen(
            device: testDevice,
            localIpAddress: localIpAddress,
          ),
        ),
      );
    }

    testWidgets('Renders AppBar, tabs, and connection badge', (tester) async {
      final repo = AppLimitsRepository(httpClient: testMockClient);

      await tester.pumpWidget(
        buildTestScreen(
          appLimitsRepo: repo,
          localIpAddress: '192.168.1.100',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App-Limits & Sperren'), findsOneWidget);
      expect(find.text('Kind-Tablet'), findsOneWidget);
      expect(find.text('LAN Direct'), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_blacklist')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_categories')), findsOneWidget);
    });

    testWidgets('Tab 1: displays empty state and opens block app modal', (tester) async {
      final repo = AppLimitsRepository(httpClient: testMockClient);
      repo.state = repo.state.copyWith(blacklistedPackages: []);

      await tester.pumpWidget(
        buildTestScreen(appLimitsRepo: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Keine Apps gesperrt'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_add_blacklist')), findsOneWidget);

      // Tap "App sperren"
      await tester.tap(find.byKey(const ValueKey('btn_add_blacklist')));
      await tester.pumpAndSettle();

      // Bottom sheet is visible
      expect(find.text('App sperren'), findsWidgets);
      expect(find.text('Apps durchsuchen...'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_modal_done')), findsOneWidget);

      // Tap Done to close modal
      await tester.tap(find.byKey(const ValueKey('btn_modal_done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('btn_modal_done')), findsNothing);
    });

    testWidgets('Tab 1: unblocks app when unblock button is pressed', (tester) async {
      final repo = AppLimitsRepository(httpClient: testMockClient);
      repo.state = repo.state.copyWith(
        blacklistedPackages: ['com.google.android.apps.chromecast.app'],
      );

      await tester.pumpWidget(
        buildTestScreen(
          appLimitsRepo: repo,
          localIpAddress: '192.168.1.100',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Google Home'), findsOneWidget);
      expect(find.text('Gesperrt'), findsOneWidget);

      final unblockBtn = find.byKey(
        const ValueKey('btn_unblock_com.google.android.apps.chromecast.app'),
      );
      expect(unblockBtn, findsOneWidget);

      await tester.tap(unblockBtn);
      await tester.pumpAndSettle();

      expect(repo.state.blacklistedPackages, isEmpty);
      expect(find.text('„Google Home“ wurde entsperrt.'), findsOneWidget);
    });

    testWidgets('Tab 2: renders category cards with bonus buttons and grants bonus', (tester) async {
      final repo = AppLimitsRepository(httpClient: testMockClient);

      await tester.pumpWidget(
        buildTestScreen(
          appLimitsRepo: repo,
          localIpAddress: '192.168.1.100',
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 2
      await tester.tap(find.byKey(const ValueKey('tab_categories')));
      await tester.pumpAndSettle();

      expect(find.text('Spiele'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);

      final bonus15Btn = find.byKey(const ValueKey('btn_bonus_15_cat-games'));
      expect(bonus15Btn, findsOneWidget);

      await tester.tap(bonus15Btn);
      await tester.pumpAndSettle();

      final gamesCat = repo.state.categories.firstWhere((c) => c.id == 'cat-games');
      expect(gamesCat.bonusMinutes, 15);
      expect(find.text('+15 Min. Bonus für „Spiele“ hinzugefügt!'), findsOneWidget);
    });

    testWidgets('Tab 2: opens new category dialog, fills name, and saves category', (tester) async {
      final repo = AppLimitsRepository(httpClient: testMockClient);

      await tester.pumpWidget(
        buildTestScreen(
          appLimitsRepo: repo,
          localIpAddress: '192.168.1.100',
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 2
      await tester.tap(find.byKey(const ValueKey('tab_categories')));
      await tester.pumpAndSettle();

      final newCatBtn = find.byKey(const ValueKey('btn_new_category'));
      expect(newCatBtn, findsOneWidget);

      await tester.tap(newCatBtn);
      await tester.pumpAndSettle();

      expect(find.text('Neue Zeit-Kategorie'), findsOneWidget);
      expect(find.byKey(const ValueKey('input_category_name')), findsOneWidget);

      // Enter name
      await tester.enterText(
        find.byKey(const ValueKey('input_category_name')),
        'Lern-Apps',
      );
      await tester.pumpAndSettle();

      // Select limit chip 45m
      await tester.tap(find.byKey(const ValueKey('chip_limit_45')));
      await tester.pumpAndSettle();

      // Save category
      await tester.tap(find.byKey(const ValueKey('btn_save_category')));
      await tester.pumpAndSettle();

      expect(repo.state.categories.any((c) => c.name == 'Lern-Apps'), isTrue);
      expect(find.text('Kategorie „Lern-Apps“ erfolgreich gespeichert.'), findsOneWidget);
    });

    testWidgets('Tab 2: deletes category on confirmation', (tester) async {
      final repo = AppLimitsRepository(httpClient: testMockClient);

      await tester.pumpWidget(
        buildTestScreen(
          appLimitsRepo: repo,
          localIpAddress: '192.168.1.100',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tab_categories')));
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(const ValueKey('btn_delete_category_cat-games'));
      expect(deleteBtn, findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.text('Kategorie löschen?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_delete_category_button')));
      await tester.pumpAndSettle();

      expect(repo.state.categories.any((c) => c.id == 'cat-games'), isFalse);
      expect(find.text('Kategorie „Spiele“ gelöscht.'), findsOneWidget);
    });
  });

  group('VolumeControlScreen Quick Action Card Integration Tests', () {
    testWidgets('VolumeControlScreen renders App-Limits & Sperren quick action card and navigates to AppLimitsScreen', (tester) async {
      final volRepo = VolumeRepository();
      final appLimitsRepo = AppLimitsRepository(httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VolumeRepository>.value(value: volRepo),
            ChangeNotifierProvider<AppLimitsRepository>.value(value: appLimitsRepo),
          ],
          child: MaterialApp(
            home: VolumeControlScreen(
              device: testDevice,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final appLimitsCard = find.byKey(const ValueKey('action_app_limits_button'));
      expect(appLimitsCard, findsOneWidget);
      expect(find.text('App-Limits & Sperren'), findsOneWidget);

      await tester.tap(appLimitsCard);
      await tester.pumpAndSettle();

      // Should have navigated to AppLimitsScreen
      expect(find.byType(AppLimitsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_blacklist')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_categories')), findsOneWidget);
    });
  });
}
