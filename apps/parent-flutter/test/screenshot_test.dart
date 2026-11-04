// ignore_for_file: subtype_of_sealed_class
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/screenshot/screenshot_model.dart';
import 'package:parent_app/screenshot/screenshot_repository.dart';
import 'package:parent_app/screenshot/screenshot_screen.dart';
import 'package:parent_app/volume/volume_repository.dart';

void main() {
  group('ScreenshotItem Model Tests', () {
    test('Constructs with required and optional properties', () {
      final now = DateTime(2026, 11, 1, 14, 30, 45);
      final item = ScreenshotItem(
        id: 'test-shot-1',
        timestamp: now,
        base64Image: 'dGVzdC1iYXNlNjQ=',
        deviceModel: 'Samsung Galaxy Tab A9',
        foregroundApp: 'YouTube Kids',
        foregroundPackage: 'com.google.android.apps.youtube.kids',
      );

      expect(item.id, 'test-shot-1');
      expect(item.timestamp, now);
      expect(item.base64Image, 'dGVzdC1iYXNlNjQ=');
      expect(item.deviceModel, 'Samsung Galaxy Tab A9');
      expect(item.foregroundApp, 'YouTube Kids');
      expect(item.foregroundPackage, 'com.google.android.apps.youtube.kids');
    });

    test('toJson and fromJson round-trip with foregroundApp and foregroundPackage', () {
      final timestamp = DateTime(2026, 11, 1, 15, 20, 10);
      final original = ScreenshotItem(
        id: 'round-trip-id',
        timestamp: timestamp,
        base64Image: 'QUJDREVGR0g=',
        deviceModel: 'Pixel Tablet',
        foregroundApp: 'Roblox',
        foregroundPackage: 'com.roblox.client',
      );

      final json = original.toJson();
      expect(json['id'], 'round-trip-id');
      expect(json['base64Image'], 'QUJDREVGR0g=');
      expect(json['deviceModel'], 'Pixel Tablet');
      expect(json['foregroundApp'], 'Roblox');
      expect(json['foregroundPackage'], 'com.roblox.client');
      expect(json['timestamp'], timestamp.toIso8601String());

      final restored = ScreenshotItem.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.timestamp, original.timestamp);
      expect(restored.base64Image, original.base64Image);
      expect(restored.deviceModel, original.deviceModel);
      expect(restored.foregroundApp, original.foregroundApp);
      expect(restored.foregroundPackage, original.foregroundPackage);
      expect(restored, equals(original));
    });

    test('fromJson handles epoch millisecond timestamp and alternate image keys', () {
      const epochMs = 1700000000000;
      final expectedTime = DateTime.fromMillisecondsSinceEpoch(epochMs);

      // Using 'image' key instead of 'base64Image'
      final json1 = {
        'id': 'alt-key-1',
        'timestamp': epochMs,
        'image': 'aW1hZ2UtZGF0YQ==',
        'deviceModel': 'Galaxy A54',
        'foregroundApp': 'Minecraft',
        'foregroundPackage': 'com.mojang.minecraftpe',
      };
      final item1 = ScreenshotItem.fromJson(json1);
      expect(item1.id, 'alt-key-1');
      expect(item1.timestamp, expectedTime);
      expect(item1.base64Image, 'aW1hZ2UtZGF0YQ==');
      expect(item1.foregroundApp, 'Minecraft');
      expect(item1.foregroundPackage, 'com.mojang.minecraftpe');

      // Using 'screenshot' key
      final json2 = {
        'id': 'alt-key-2',
        'screenshot': 'c2NyZWVuc2hvdA==',
      };
      final item2 = ScreenshotItem.fromJson(json2);
      expect(item2.id, 'alt-key-2');
      expect(item2.base64Image, 'c2NyZWVuc2hvdA==');
      expect(item2.deviceModel, isNull);
      expect(item2.foregroundApp, isNull);
      expect(item2.foregroundPackage, isNull);
    });

    test('Formatting helpers produce correct human-readable strings', () {
      final date = DateTime(2026, 5, 4, 9, 7, 3);
      final item = ScreenshotItem(
        id: 'fmt-id',
        timestamp: date,
        base64Image: 'YWJj',
      );

      expect(item.formattedTime, '09:07:03 Uhr');
      expect(item.formattedDate, '04.05.2026');
      expect(item.formattedDateTime, '04.05.2026 09:07:03 Uhr');
    });

    test('copyWith works correctly with foregroundApp and foregroundPackage', () {
      final original = ScreenshotItem(
        id: 'cp-1',
        timestamp: DateTime(2026, 1, 1),
        base64Image: 'aW1nMQ==',
        deviceModel: 'Model A',
        foregroundApp: 'App A',
        foregroundPackage: 'pkg.a',
      );

      final modified = original.copyWith(
        base64Image: 'aW1nMg==',
        deviceModel: 'Model B',
        foregroundApp: 'App B',
        foregroundPackage: 'pkg.b',
      );

      expect(modified.id, 'cp-1');
      expect(modified.timestamp, DateTime(2026, 1, 1));
      expect(modified.base64Image, 'aW1nMg==');
      expect(modified.deviceModel, 'Model B');
      expect(modified.foregroundApp, 'App B');
      expect(modified.foregroundPackage, 'pkg.b');
    });

    test('toFirestoreMap generates correct structure including foregroundApp and foregroundPackage', () {
      final date = DateTime(2026, 10, 20, 18, 0, 0);
      final item = ScreenshotItem(
        id: 'fs-map-id',
        timestamp: date,
        base64Image: 'YmFzZTY0',
        deviceModel: 'Test Device',
        foregroundApp: 'Chrome',
        foregroundPackage: 'com.android.chrome',
      );

      final map = item.toFirestoreMap();
      expect(map['id'], 'fs-map-id');
      expect(map['base64Image'], 'YmFzZTY0');
      expect(map['deviceModel'], 'Test Device');
      expect(map['foregroundApp'], 'Chrome');
      expect(map['foregroundPackage'], 'com.android.chrome');
      expect(map['timestamp'], isNotNull);
    });

    test('equality and hashCode include foregroundApp and foregroundPackage', () {
      final now = DateTime(2026, 11, 1);
      final item1 = ScreenshotItem(
        id: 'eq-1',
        timestamp: now,
        base64Image: 'img',
        foregroundApp: 'App 1',
        foregroundPackage: 'pkg.1',
      );
      final item2 = ScreenshotItem(
        id: 'eq-1',
        timestamp: now,
        base64Image: 'img',
        foregroundApp: 'App 1',
        foregroundPackage: 'pkg.1',
      );
      final item3 = ScreenshotItem(
        id: 'eq-1',
        timestamp: now,
        base64Image: 'img',
        foregroundApp: 'App 2',
        foregroundPackage: 'pkg.1',
      );

      expect(item1, equals(item2));
      expect(item1.hashCode, equals(item2.hashCode));
      expect(item1, isNot(equals(item3)));
    });
  });

  group('Screenshot Error Translation Tests', () {
    test('translates permission-denied errors to friendly guidance', () {
      const rawError1 = 'cloud_firestore/permission-denied';
      final translated1 = ScreenshotRepository.formatError(rawError1);
      expect(translated1, contains('permission-denied'));
      expect(translated1, contains('Firebase Console'));
      expect(translated1, contains('screenshots'));

      const rawError2 = '[cloud_firestore/permission-denied] Missing or insufficient permissions.';
      final translated2 = ScreenshotRepository.formatError(rawError2);
      expect(translated2, contains('Firebase Console'));
      expect(translated2, contains('pairings/{childToken}/screenshots'));

      expect(ScreenshotRepository.isPermissionDenied(rawError1), isTrue);
      expect(ScreenshotRepository.isPermissionDenied(rawError2), isTrue);
    });

    test('preserves non-permission errors as-is', () {
      const normalError = 'Failed host lookup: android.local';
      expect(ScreenshotRepository.formatError(normalError), equals(normalError));
      expect(ScreenshotRepository.isPermissionDenied(normalError), isFalse);
    });

    test('hasPermissionError getter reacts to repository error state', () {
      final repo = ScreenshotRepository();
      expect(repo.hasPermissionError, isFalse);

      repo.lastErrorForTesting = 'cloud_firestore/permission-denied';
      expect(repo.hasPermissionError, isTrue);

      repo.lastErrorForTesting = 'Network timed out';
      expect(repo.hasPermissionError, isFalse);
    });
  });

  group('ScreenshotRepository Tests', () {
    test('Initial repository state is empty and not capturing', () {
      final repo = ScreenshotRepository();

      expect(repo.history, isEmpty);
      expect(repo.isCapturing, isFalse);
      expect(repo.latestScreenshot, isNull);
    });

    test('setHistoryForTesting updates state and notifies listeners', () {
      final repo = ScreenshotRepository();
      bool listenerNotified = false;
      repo.addListener(() {
        listenerNotified = true;
      });

      final item = ScreenshotItem(
        id: 'shot-99',
        timestamp: DateTime.now(),
        base64Image: 'ZXhhbXBsZQ==',
        deviceModel: 'Xiaomi Pad',
        foregroundApp: 'Disney+',
        foregroundPackage: 'com.disney.disneyplus',
      );

      repo.setHistoryForTesting([item]);

      expect(repo.history.length, 1);
      expect(repo.latestScreenshot, equals(item));
      expect(listenerNotified, isTrue);
    });

    test('captureScreenshot succeeds via direct LAN HTTP and parses foregroundApp / foregroundPackage', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.120:8085/take_screenshot');
        expect(request.method, 'POST');

        final responseJson = {
          'id': 'lan-shot-42',
          'base64Image': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
          'deviceModel': 'Lenovo Tab M10',
          'foregroundApp': 'TikTok',
          'foregroundPackage': 'com.zhiliaoapp.musically',
          'timestamp': 1700000050000,
        };
        return http.Response(jsonEncode(responseJson), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final repo = ScreenshotRepository(httpClient: mockClient);

      bool capturingObserved = false;
      repo.addListener(() {
        if (repo.isCapturing) {
          capturingObserved = true;
        }
      });

      final result = await repo.captureScreenshot(
        'child_device_fcm_token_123',
        localIpAddress: '192.168.1.120',
      );

      expect(capturingObserved, isTrue);
      expect(repo.isCapturing, isFalse);
      expect(result, isNotNull);
      expect(result!.id, 'lan-shot-42');
      expect(result.deviceModel, 'Lenovo Tab M10');
      expect(result.foregroundApp, 'TikTok');
      expect(result.foregroundPackage, 'com.zhiliaoapp.musically');
      expect(result.base64Image, contains('iVBORw0KGgo'));
      expect(repo.history.length, 1);
      expect(repo.latestScreenshot, equals(result));
    });

    test('captureScreenshot handles raw base64 string response from LAN HTTP', () async {
      const rawBase64 = 'iVBORw0KGgoAAAANSUhEUg==';
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.200:8085/take_screenshot');
        return http.Response(jsonEncode(rawBase64), 200);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.captureScreenshot(
        'child_device_fcm_token_456',
        localIpAddress: '192.168.1.200',
      );

      expect(result, isNotNull);
      expect(result!.base64Image, rawBase64);
      expect(result.foregroundApp, isNull);
      expect(result.foregroundPackage, isNull);
      expect(repo.history.length, 1);
    });

    test('captureScreenshot prevents concurrent capture attempts', () async {
      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return http.Response(jsonEncode({'base64Image': 'ZHVtbXk='}), 200);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);

      // Start first capture
      final future1 = repo.captureScreenshot('child_fcm_token', localIpAddress: '192.168.1.10');
      expect(repo.isCapturing, isTrue);

      // Attempt second capture while first is in flight
      final future2 = repo.captureScreenshot('child_fcm_token', localIpAddress: '192.168.1.10');
      final result2 = await future2;
      expect(result2, isNull);

      final result1 = await future1;
      expect(result1, isNotNull);
      expect(repo.isCapturing, isFalse);
    });

    test('captureScreenshot LAN failure falls back gracefully when firestore is null', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server error', 500);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.captureScreenshot(
        'child_token',
        localIpAddress: '192.168.1.55',
      );

      // LAN fails with 500, then fallback to firestore fails gracefully (no firestore configured in test)
      expect(result, isNull);
      expect(repo.isCapturing, isFalse);
      expect(repo.history, isEmpty);
      expect(repo.lastError, contains('500'));
    });

    test('captureScreenshot records accessibility error from LAN response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({
          'status': 'error',
          'message': 'Accessibility Service is not connected'
        }), 500);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.captureScreenshot(
        'child_token',
        localIpAddress: '192.168.1.55',
      );

      expect(result, isNull);
      expect(repo.lastError, 'Accessibility Service is not connected');
      final errorLower = repo.lastError!.toLowerCase();
      final isAccessibilityOrTimeout = errorLower.contains('accessibility') ||
          errorLower.contains('is not connected') ||
          errorLower.contains('timeout');
      expect(isAccessibilityOrTimeout, isTrue);
    });

    test('closeCurrentApp succeeds via direct LAN HTTP', () async {
      bool closeAppCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.120:8085/close_app');
        expect(request.method, 'POST');
        closeAppCalled = true;
        return http.Response(jsonEncode({'status': 'success', 'closed': true}), 200);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.closeCurrentApp(
        'child_device_fcm_token_123',
        localIpAddress: '192.168.1.120',
      );

      expect(closeAppCalled, isTrue);
      expect(result, isTrue);
    });

    test('closeCurrentApp LAN failure falls back gracefully when firestore is null', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.closeCurrentApp(
        'child_device_fcm_token_123',
        localIpAddress: '192.168.1.120',
      );

      expect(result, isFalse);
    });

    test('closeCurrentApp without localIpAddress falls back gracefully when firestore is null', () async {
      final repo = ScreenshotRepository();
      final result = await repo.closeCurrentApp('child_device_fcm_token_123');

      expect(result, isFalse);
    });

    test('lockScreen succeeds via direct LAN HTTP', () async {
      bool lockScreenCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.120:8085/lock_screen');
        expect(request.method, 'POST');
        lockScreenCalled = true;
        return http.Response(jsonEncode({'status': 'success', 'message': 'Screen locked'}), 200);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.lockScreen(
        'child_device_fcm_token_123',
        localIpAddress: '192.168.1.120',
      );

      expect(lockScreenCalled, isTrue);
      expect(result, isTrue);
    });

    test('lockScreen LAN failure falls back gracefully when firestore is null', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final repo = ScreenshotRepository(httpClient: mockClient);
      final result = await repo.lockScreen(
        'child_device_fcm_token_123',
        localIpAddress: '192.168.1.120',
      );

      expect(result, isFalse);
    });

    test('lockScreen without localIpAddress falls back gracefully when firestore is null', () async {
      final repo = ScreenshotRepository();
      final result = await repo.lockScreen('child_device_fcm_token_123');

      expect(result, isFalse);
    });

    test('deleteScreenshot removes item from history and notifies listeners', () async {
      final repo = ScreenshotRepository();
      final item1 = ScreenshotItem(
        id: 'del-1',
        timestamp: DateTime.now(),
        base64Image: 'aW1nMQ==',
      );
      final item2 = ScreenshotItem(
        id: 'del-2',
        timestamp: DateTime.now(),
        base64Image: 'aW1nMg==',
      );
      repo.setHistoryForTesting([item1, item2]);

      bool notified = false;
      repo.addListener(() => notified = true);

      final success = await repo.deleteScreenshot('child_token', 'del-1');

      expect(success, isTrue);
      expect(notified, isTrue);
      expect(repo.history.length, 1);
      expect(repo.history.first.id, 'del-2');
    });

    test('deleteScreenshot with Firestore calls delete on specific document path', () async {
      final fakeFirestore = FakeFirestore();
      final repo = ScreenshotRepository(firestore: fakeFirestore);
      final item = ScreenshotItem(
        id: 'shot-to-delete',
        timestamp: DateTime.now(),
        base64Image: 'aW1n',
      );
      repo.setHistoryForTesting([item]);

      final success = await repo.deleteScreenshot('child_device_token', 'shot-to-delete');

      expect(success, isTrue);
      expect(fakeFirestore.deletedDocPaths, contains('pairings/child_device_token/screenshots/shot-to-delete'));
      expect(repo.history, isEmpty);
    });

    test('deleteScreenshot handles Firestore error, sets lastError and preserves history', () async {
      final fakeFirestore = FakeFirestore()..throwOnDelete = true;
      final repo = ScreenshotRepository(firestore: fakeFirestore);
      final item = ScreenshotItem(
        id: 'shot-fail',
        timestamp: DateTime.now(),
        base64Image: 'aW1n',
      );
      repo.setHistoryForTesting([item]);

      final success = await repo.deleteScreenshot('child_token', 'shot-fail');

      expect(success, isFalse);
      expect(repo.hasPermissionError, isTrue);
      expect(repo.history.length, 1);
      expect(repo.history.first.id, 'shot-fail');
    });

    test('deleteAllScreenshots clears history and notifies listeners', () async {
      final repo = ScreenshotRepository();
      final item1 = ScreenshotItem(
        id: 'all-1',
        timestamp: DateTime.now(),
        base64Image: 'aW1nMQ==',
      );
      final item2 = ScreenshotItem(
        id: 'all-2',
        timestamp: DateTime.now(),
        base64Image: 'aW1nMg==',
      );
      repo.setHistoryForTesting([item1, item2]);

      bool notified = false;
      repo.addListener(() => notified = true);

      final success = await repo.deleteAllScreenshots('child_token');

      expect(success, isTrue);
      expect(notified, isTrue);
      expect(repo.history, isEmpty);
      expect(repo.latestScreenshot, isNull);
    });

    test('deleteAllScreenshots with Firestore commits batch delete for all docs', () async {
      final fakeFirestore = FakeFirestore()..existingDocIds = ['doc-1', 'doc-2', 'doc-3'];
      final repo = ScreenshotRepository(firestore: fakeFirestore);
      repo.setHistoryForTesting([
        ScreenshotItem(id: 'doc-1', timestamp: DateTime.now(), base64Image: 'aW1n'),
        ScreenshotItem(id: 'doc-2', timestamp: DateTime.now(), base64Image: 'aW1n'),
        ScreenshotItem(id: 'doc-3', timestamp: DateTime.now(), base64Image: 'aW1n'),
      ]);

      final success = await repo.deleteAllScreenshots('child_device_token');

      expect(success, isTrue);
      expect(fakeFirestore.deletedDocPaths, [
        'pairings/child_device_token/screenshots/doc-1',
        'pairings/child_device_token/screenshots/doc-2',
        'pairings/child_device_token/screenshots/doc-3',
      ]);
      expect(repo.history, isEmpty);
    });

    test('deleteAllScreenshots handles Firestore error, sets lastError and returns false', () async {
      final fakeFirestore = FakeFirestore()
        ..existingDocIds = ['doc-1']
        ..throwOnDelete = true;
      final repo = ScreenshotRepository(firestore: fakeFirestore);
      repo.setHistoryForTesting([
        ScreenshotItem(id: 'doc-1', timestamp: DateTime.now(), base64Image: 'aW1n'),
      ]);

      final success = await repo.deleteAllScreenshots('child_token');

      expect(success, isFalse);
      expect(repo.hasPermissionError, isTrue);
      expect(repo.history.length, 1);
    });
  });

  group('ScreenshotScreen Widget & Dynamic IP Tests', () {
    final testDevice = PairedDevice(
      name: 'Kind Tablet',
      fcmToken: 'test_child_fcm_token',
      lastSeen: DateTime.now(),
    );

    Widget createTestWidget({
      required ScreenshotRepository screenshotRepo,
      required VolumeRepository volumeRepo,
      String? localIpAddress,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ScreenshotRepository>.value(value: screenshotRepo),
          ChangeNotifierProvider<VolumeRepository>.value(value: volumeRepo),
        ],
        child: MaterialApp(
          home: ScreenshotScreen(
            device: testDevice,
            localIpAddress: localIpAddress,
          ),
        ),
      );
    }

    testWidgets('effectiveIp uses widget.localIpAddress when provided', (tester) async {
      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
          localIpAddress: '192.168.1.42',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LAN Direct'), findsOneWidget);
      expect(find.text('Cloud Sync'), findsNothing);
    });

    testWidgets('effectiveIp dynamically resolves from VolumeRepository when widget.localIpAddress is null', (tester) async {
      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
          localIpAddress: null,
        ),
      );
      await tester.pumpAndSettle();

      // Initially null -> Cloud Sync
      expect(find.text('Cloud Sync'), findsOneWidget);
      expect(find.text('LAN Direct'), findsNothing);

      // Dynamically assign localIpAddress to VolumeRepository
      volumeRepo.localIpAddress = '192.168.1.88';
      volumeRepo.notifyListeners();
      await tester.pumpAndSettle();

      // Now dynamically resolved -> LAN Direct
      expect(find.text('LAN Direct'), findsOneWidget);
      expect(find.text('Cloud Sync'), findsNothing);
    });

    testWidgets('permission error renders dedicated informative banner with rules hint', (tester) async {
      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      screenshotRepo.lastErrorForTesting =
          ScreenshotRepository.formatError('cloud_firestore/permission-denied');

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('screenshot_permission_error_banner')), findsOneWidget);
      expect(find.text('Firestore-Berechtigung verweigert'), findsOneWidget);
      expect(find.textContaining('pairings/{childToken}/screenshots'), findsOneWidget);
    });

    testWidgets('general error renders standard error banner without permission card', (tester) async {
      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      screenshotRepo.lastErrorForTesting = 'Connection reset by peer';

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('screenshot_permission_error_banner')), findsNothing);
      expect(find.textContaining('Screenshot konnte nicht empfangen werden: Connection reset by peer'), findsOneWidget);
    });

    testWidgets('lock screen button is rendered in action area and tapping opens confirmation dialog', (tester) async {
      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Top action button is visible even without screenshots
      final lockBtn = find.byKey(const ValueKey('action_lock_screen_button'));
      expect(lockBtn, findsOneWidget);
      expect(find.text('Bildschirm sperren'), findsOneWidget);
      expect(find.byIcon(Icons.screen_lock_portrait_rounded), findsOneWidget);

      // Tap button to open dialog
      await tester.tap(lockBtn);
      await tester.pumpAndSettle();

      expect(find.text('Tablet-Bildschirm sperren?'), findsOneWidget);
      expect(find.text('Möchtest du den Bildschirm des Tablets jetzt sofort ausschalten und sperren?'), findsOneWidget);
      expect(find.text('Abbrechen'), findsOneWidget);
      expect(find.text('Jetzt sperren'), findsOneWidget);

      // Cancel dismisses dialog
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Tablet-Bildschirm sperren?'), findsNothing);
    });

    testWidgets('confirming lock screen dialog invokes lockScreen and displays success SnackBar', (tester) async {
      bool lockCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/lock_screen') {
          lockCalled = true;
          return http.Response(jsonEncode({'status': 'success', 'message': 'Screen locked'}), 200);
        }
        return http.Response('Not found', 404);
      });

      final screenshotRepo = ScreenshotRepository(httpClient: mockClient);
      final volumeRepo = VolumeRepository();

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
          localIpAddress: '192.168.1.50',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('action_lock_screen_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jetzt sperren'));
      await tester.pumpAndSettle();

      expect(lockCalled, isTrue);
      expect(find.text('Tablet-Bildschirm wurde gesperrt.'), findsOneWidget);
    });

    testWidgets('failed lockScreen displays error SnackBar', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response('Error', 500);
      });

      final screenshotRepo = ScreenshotRepository(httpClient: mockClient);
      final volumeRepo = VolumeRepository();

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
          localIpAddress: '192.168.1.50',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('action_lock_screen_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jetzt sperren'));
      await tester.pumpAndSettle();

      expect(find.text('Bildschirm konnte nicht gesperrt werden. Ist das Gerät online?'), findsOneWidget);
    });

    testWidgets('when screenshot is loaded, both action button and card button are available', (tester) async {
      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      final item = ScreenshotItem(
        id: 'shot-card-test',
        timestamp: DateTime.now(),
        base64Image: 'dGVzdA==',
        foregroundApp: 'YouTube Kids',
        foregroundPackage: 'com.google.android.apps.youtube.kids',
      );
      screenshotRepo.setHistoryForTesting([item]);

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('action_lock_screen_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('card_lock_screen_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('close_app_button')), findsOneWidget);
      expect(find.text('Tablet sperren'), findsOneWidget);
      expect(find.text('App sofort beenden'), findsOneWidget);

      // Scroll to and tap card lock screen button opens confirmation dialog
      await tester.ensureVisible(find.byKey(const ValueKey('card_lock_screen_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('card_lock_screen_button')));
      await tester.pumpAndSettle();

      expect(find.text('Tablet-Bildschirm sperren?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Tablet-Bildschirm sperren?'), findsNothing);
    });

    testWidgets('delete button on latest screenshot card prompts confirmation dialog and deletes on confirm', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      final item1 = ScreenshotItem(
        id: 'shot-card-1',
        timestamp: DateTime(2026, 11, 4, 10, 0),
        base64Image: 'dGVzdDE=',
        foregroundApp: 'YouTube Kids',
      );
      final item2 = ScreenshotItem(
        id: 'shot-card-2',
        timestamp: DateTime(2026, 11, 4, 9, 30),
        base64Image: 'dGVzdDI=',
        foregroundApp: 'Scratch Jr',
      );
      screenshotRepo.setHistoryForTesting([item1, item2]);

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      final deleteLatestBtn = find.byKey(const ValueKey('delete_latest_screenshot_button'));
      expect(deleteLatestBtn, findsOneWidget);

      // Tap delete button -> dialog appears
      await tester.tap(deleteLatestBtn);
      await tester.pumpAndSettle();

      expect(find.text('Screenshot löschen?'), findsOneWidget);
      expect(find.text('Abbrechen'), findsOneWidget);
      expect(find.text('Löschen'), findsOneWidget);

      // Cancel dismissal
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Screenshot löschen?'), findsNothing);
      expect(screenshotRepo.history.length, 2);

      // Tap delete button again and confirm
      await tester.tap(deleteLatestBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await tester.pumpAndSettle();

      expect(find.text('Screenshot gelöscht.'), findsOneWidget);
      expect(screenshotRepo.history.length, 1);
      expect(screenshotRepo.latestScreenshot!.id, 'shot-card-2');
    });

    testWidgets('delete button in fullscreen viewer prompts confirmation dialog, closes viewer, and deletes screenshot', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      final item = ScreenshotItem(
        id: 'shot-fullscreen-1',
        timestamp: DateTime(2026, 11, 4, 11, 0),
        base64Image: 'dGVzdA==',
        foregroundApp: 'Minecraft',
      );
      screenshotRepo.setHistoryForTesting([item]);

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Tap preview container to open fullscreen viewer
      await tester.tap(find.text('Vergrößern'));
      await tester.pumpAndSettle();

      final fsDeleteBtn = find.byKey(const ValueKey('fullscreen_delete_button'));
      expect(fsDeleteBtn, findsOneWidget);

      // Tap fullscreen delete button
      await tester.tap(fsDeleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Screenshot löschen?'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await tester.pumpAndSettle();

      // Fullscreen viewer closed, SnackBar shown, empty state displayed
      expect(find.byKey(const ValueKey('fullscreen_delete_button')), findsNothing);
      expect(find.text('Screenshot gelöscht.'), findsOneWidget);
      expect(screenshotRepo.history, isEmpty);
      expect(find.text('Noch kein Screenshot vorhanden'), findsOneWidget);
    });

    testWidgets('individual delete button in history gallery prompts dialog and deletes that item', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      final item1 = ScreenshotItem(
        id: 'item-h1',
        timestamp: DateTime(2026, 11, 4, 12, 0),
        base64Image: 'dGVzdDE=',
        foregroundApp: 'App 1',
      );
      final item2 = ScreenshotItem(
        id: 'item-h2',
        timestamp: DateTime(2026, 11, 4, 11, 0),
        base64Image: 'dGVzdDI=',
        foregroundApp: 'App 2',
      );
      screenshotRepo.setHistoryForTesting([item1, item2]);

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      final deleteH2Btn = find.byKey(const ValueKey('delete_history_screenshot_item-h2'));
      await tester.ensureVisible(deleteH2Btn);
      await tester.pumpAndSettle();

      await tester.tap(deleteH2Btn);
      await tester.pumpAndSettle();

      expect(find.text('Screenshot löschen?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await tester.pumpAndSettle();

      expect(find.text('Screenshot gelöscht.'), findsOneWidget);
      expect(screenshotRepo.history.length, 1);
      expect(screenshotRepo.history.first.id, 'item-h1');
      expect(find.byKey(const ValueKey('delete_history_screenshot_item-h2')), findsNothing);
    });

    testWidgets('delete all button in history gallery prompts confirmation dialog and deletes all screenshots', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final screenshotRepo = ScreenshotRepository();
      final volumeRepo = VolumeRepository();

      screenshotRepo.setHistoryForTesting([
        ScreenshotItem(id: 'all-h1', timestamp: DateTime.now(), base64Image: 'dGVzdDE='),
        ScreenshotItem(id: 'all-h2', timestamp: DateTime.now(), base64Image: 'dGVzdDI='),
      ]);

      await tester.pumpWidget(
        createTestWidget(
          screenshotRepo: screenshotRepo,
          volumeRepo: volumeRepo,
        ),
      );
      await tester.pumpAndSettle();

      final deleteAllBtn = find.byKey(const ValueKey('delete_all_screenshots_button'));
      await tester.ensureVisible(deleteAllBtn);
      await tester.pumpAndSettle();
      expect(find.text('Alle löschen'), findsOneWidget);

      // Tap "Alle löschen" -> confirmation dialog appears
      await tester.tap(deleteAllBtn);
      await tester.pumpAndSettle();

      expect(find.text('Alle Screenshots löschen?'), findsOneWidget);
      expect(find.textContaining('Möchtest du alle 2 Aufnahmen wirklich unwiderruflich löschen?'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(screenshotRepo.history.length, 2);

      // Tap again and confirm
      await tester.tap(deleteAllBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm_delete_all_button')));
      await tester.pumpAndSettle();

      expect(find.text('Alle Screenshots wurden gelöscht.'), findsOneWidget);
      expect(screenshotRepo.history, isEmpty);
      expect(find.text('Noch kein Screenshot vorhanden'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete_all_screenshots_button')), findsNothing);
    });
  });
}

class FakeFirestore extends Fake implements FirebaseFirestore {
  final List<String> deletedDocPaths = [];
  bool throwOnDelete = false;
  bool throwOnGet = false;
  List<String> existingDocIds = [];

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference(this, collectionPath);
  }

  @override
  WriteBatch batch() => FakeWriteBatch(this);
}

class FakeCollectionReference extends Fake implements CollectionReference<Map<String, dynamic>> {
  final FakeFirestore firestoreInstance;
  @override
  final String path;
  FakeCollectionReference(this.firestoreInstance, this.path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? docId]) {
    return FakeDocumentReference(firestoreInstance, '$path/$docId');
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    if (firestoreInstance.throwOnGet) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing permissions');
    }
    return FakeQuerySnapshot(
      firestoreInstance.existingDocIds
          .map((id) => FakeQueryDocumentSnapshot(firestoreInstance, '$path/$id', id))
          .toList(),
    );
  }
}

class FakeDocumentReference extends Fake implements DocumentReference<Map<String, dynamic>> {
  final FakeFirestore firestoreInstance;
  final String docPath;
  FakeDocumentReference(this.firestoreInstance, this.docPath);

  @override
  String get path => docPath;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference(firestoreInstance, '$docPath/$collectionPath');
  }

  @override
  Future<void> delete() async {
    if (firestoreInstance.throwOnDelete) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Delete failed');
    }
    firestoreInstance.deletedDocPaths.add(docPath);
  }
}

class FakeQuerySnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;
  FakeQuerySnapshot(this._docs);

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class FakeQueryDocumentSnapshot extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final FakeFirestore firestoreInstance;
  final String docPath;
  final String _id;
  FakeQueryDocumentSnapshot(this.firestoreInstance, this.docPath, this._id);

  @override
  String get id => _id;

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      FakeDocumentReference(firestoreInstance, docPath);
}

class FakeWriteBatch extends Fake implements WriteBatch {
  final FakeFirestore firestoreInstance;
  final List<DocumentReference> deletedReferences = [];
  FakeWriteBatch(this.firestoreInstance);

  @override
  void delete(DocumentReference document) {
    deletedReferences.add(document);
  }

  @override
  Future<void> commit() async {
    if (firestoreInstance.throwOnDelete) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Batch failed');
    }
    for (final ref in deletedReferences) {
      firestoreInstance.deletedDocPaths.add(ref.path);
    }
  }
}
