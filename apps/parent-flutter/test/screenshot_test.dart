import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/screenshot/screenshot_model.dart';
import 'package:parent_app/screenshot/screenshot_repository.dart';

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
  });
}
