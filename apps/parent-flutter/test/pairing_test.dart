import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/pairing/pairing_screen.dart';
import 'package:parent_app/volume/volume_control_screen.dart';
import 'package:parent_app/volume/volume_repository.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/l10n/app_strings.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppStrings.manualLocale = const Locale('de');
  });

  tearDown(() {
    AppStrings.manualLocale = null;
  });

  group('QR Code Parsing & PairingQrPayload Tests', () {
    test('Parses standard v1 JSON payload correctly', () {
      const jsonStr =
          '{"v":1,"deviceId":"tablet-007","deviceName":"Felix Pixel","ip":"192.168.1.150","port":8085,"token":"token-abc-123"}';
      final payload = PairingQrPayload.tryParse(jsonStr);

      expect(payload, isNotNull);
      expect(payload!.version, 1);
      expect(payload.deviceId, 'tablet-007');
      expect(payload.deviceName, 'Felix Pixel');
      expect(payload.ip, '192.168.1.150');
      expect(payload.port, 8085);
      expect(payload.token, 'token-abc-123');
    });

    test('Parses JSON payload with string port correctly', () {
      const jsonStr =
          '{"v":1,"deviceId":"dev-1","deviceName":"Child Phone","ip":"10.0.0.5","port":"8085","token":"tok"}';
      final payload = PairingQrPayload.tryParse(jsonStr);

      expect(payload, isNotNull);
      expect(payload!.port, 8085);
      expect(payload.ip, '10.0.0.5');
    });

    test('Parses plain IP string for backwards compatibility', () {
      final payload = PairingQrPayload.tryParse('192.168.1.200');

      expect(payload, isNotNull);
      expect(payload!.ip, '192.168.1.200');
      expect(payload.port, 8085);
      expect(payload.token, '192.168.1.200');
    });

    test('Parses plain IP:port string for backwards compatibility', () {
      final payload = PairingQrPayload.tryParse('192.168.1.200:9090');

      expect(payload, isNotNull);
      expect(payload!.ip, '192.168.1.200');
      expect(payload.port, 9090);
    });

    test('Parses plain token string for backwards compatibility', () {
      final payload = PairingQrPayload.tryParse('fcm-token-xyz-987');

      expect(payload, isNotNull);
      expect(payload!.token, 'fcm-token-xyz-987');
      expect(payload.ip, '');
      expect(payload.port, 8085);
    });

    test('Returns null for empty or whitespace raw string', () {
      expect(PairingQrPayload.tryParse(''), isNull);
      expect(PairingQrPayload.tryParse('   '), isNull);
    });
  });

  group('PairedDevice Model Tests', () {
    test('Default port is 8085 and backwards compatible getters work', () {
      final now = DateTime.now();
      final device = PairedDevice(
        id: 'dev-1',
        name: 'Felix',
        token: 'tok-123',
        localIpAddress: '192.168.1.50',
        lastSeen: now,
      );

      expect(device.id, 'dev-1');
      expect(device.port, 8085);
      expect(device.fcmToken, 'tok-123');
      expect(device.ipAddress, '192.168.1.50');
      expect(device.localIpAddress, '192.168.1.50');
    });

    test('toJson and fromJson preserve all fields', () {
      final now = DateTime.now();
      final device = PairedDevice(
        id: 'dev-42',
        name: 'Felix Tab',
        token: 'secret-token',
        localIpAddress: '192.168.2.10',
        port: 8085,
        lastSeen: now,
      );

      final jsonMap = device.toJson();
      final restored = PairedDevice.fromJson(jsonMap);

      expect(restored.id, 'dev-42');
      expect(restored.name, 'Felix Tab');
      expect(restored.token, 'secret-token');
      expect(restored.fcmToken, 'secret-token');
      expect(restored.localIpAddress, '192.168.2.10');
      expect(restored.ipAddress, '192.168.2.10');
      expect(restored.port, 8085);
      expect(restored.lastSeen.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });
  });

  group('Connectivity & Status Check Tests', () {
    late PairingRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repository = PairingRepository();
    });

    test('verifyDeviceConnectivity succeeds with 200 OK and token header', () async {
      final mockClient = MockHttpClient((req) async {
        expect(req.url.toString(), 'http://192.168.1.50:8085/status');
        expect(req.headers['X-Buddy-Token'], 'valid-token-123');
        return http.Response(
          jsonEncode({
            'status': 'online',
            'deviceId': 'test-dev',
            'deviceName': 'Test Device',
            'version': '1.0.0',
          }),
          200,
        );
      });

      final result = await repository.verifyDeviceConnectivity(
        '192.168.1.50',
        8085,
        'valid-token-123',
        client: mockClient,
      );

      expect(result, isTrue);
    });

    test('verifyDeviceConnectivity fails on HTTP 500', () async {
      final mockClient = MockHttpClient((req) async {
        return http.Response('Internal Error', 500);
      });

      final result = await repository.verifyDeviceConnectivity(
        '192.168.1.50',
        8085,
        'valid-token-123',
        client: mockClient,
      );

      expect(result, isFalse);
    });

    test('verifyDeviceConnectivity fails on network exception', () async {
      final mockClient = MockHttpClient((req) async {
        throw Exception('Socket timeout');
      });

      final result = await repository.verifyDeviceConnectivity(
        '192.168.1.50',
        8085,
        'valid-token-123',
        client: mockClient,
      );

      expect(result, isFalse);
    });
  });

  group('PairingScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Entering IP/code connects, saves device, shows banner, and navigates',
        (tester) async {
      final mockClient = MockHttpClient((req) async {
        if (req.url.path == '/status') {
          return http.Response(
            jsonEncode({
              'status': 'online',
              'deviceId': 'dev-widget-test',
              'deviceName': 'Felix Test Tab',
            }),
            200,
          );
        }
        if (req.url.path == '/volume_report') {
          return http.Response(
            jsonEncode({
              'type': 'VOLUME_REPORT',
              'mediaVolume': 7,
              'ringtoneVolume': 5,
              'alarmVolume': 10,
              'maxMediaVolume': 15,
              'maxRingtoneVolume': 15,
              'maxAlarmVolume': 15,
              'isMuted': false,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final volumeRepo = VolumeRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VolumeRepository>.value(value: volumeRepo),
          ],
          child: MaterialApp(
            home: PairingScreen(
              httpClient: mockClient,
            ),
          ),
        ),
      );

      expect(find.text('Kinder-Gerät lokal koppeln'), findsOneWidget);

      // Enter IP address in code/IP text field
      final textField = find.byType(TextField).at(1);
      await tester.enterText(textField, '192.168.1.77');
      await tester.pump();

      // Tap Verbinden button
      final connectBtn = find.widgetWithText(ElevatedButton, 'Verbinden');
      await tester.tap(connectBtn);
      await tester.pump(); // Start loading
      await tester.pump(const Duration(milliseconds: 100)); // Complete async pairing
      await tester.pumpAndSettle();

      // Success SnackBar should appear
      expect(find.text('Erfolgreich gekoppelt!'), findsOneWidget);

      // Should have navigated to VolumeControlScreen
      expect(find.byType(VolumeControlScreen), findsOneWidget);

      // Verify SharedPreferences persistence
      final repo = PairingRepository();
      final paired = await repo.loadPairedDevice();
      expect(paired, isNotNull);
      expect(paired!.localIpAddress, '192.168.1.77');
      expect(paired.port, 8085);
    });

    testWidgets('Unreachable IP shows informative error banner', (tester) async {
      final mockClient = MockHttpClient((req) async {
        throw Exception('Connection refused');
      });

      await tester.pumpWidget(
        MaterialApp(
          home: PairingScreen(
            httpClient: mockClient,
          ),
        ),
      );

      final textField = find.byType(TextField).at(1);
      await tester.enterText(textField, '192.168.1.99');
      await tester.pump();

      final connectBtn = find.widgetWithText(ElevatedButton, 'Verbinden');
      await tester.tap(connectBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.textContaining('Verbindung zum Gerät unter 192.168.1.99:8085 fehlgeschlagen'), findsOneWidget);
      expect(find.byType(VolumeControlScreen), findsNothing);
    });

    testWidgets('Tapping QR scan opens scanner and back button returns without hanging', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PairingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final qrButton = find.byIcon(Icons.qr_code_scanner);
      expect(qrButton, findsOneWidget);

      await tester.tap(qrButton);
      await tester.pump();

      // Scanner screen should be visible
      expect(find.byType(MobileScanner), findsOneWidget);
      expect(find.text('QR Code scannen'), findsOneWidget);

      // Tap back button
      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pump();

      // Should return to pairing screen
      expect(find.text('Kinder-Gerät lokal koppeln'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
