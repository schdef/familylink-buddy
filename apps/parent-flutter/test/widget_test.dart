import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/pairing/device_list_screen.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/l10n/app_strings.dart';

class MockPairingRepository extends PairingRepository {
  final List<PairedDevice> mockDevices;
  final bool isOnline;
  final Duration delay;

  MockPairingRepository({
    required this.mockDevices,
    this.isOnline = true,
    this.delay = Duration.zero,
  });

  @override
  Future<List<PairedDevice>> loadPairedDevices() async => mockDevices;

  @override
  Future<bool> verifyDeviceConnectivity(
    String ip,
    int port,
    String token, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return isOnline;
  }
}

void main() {
  setUp(() => AppStrings.manualLocale = const Locale('de'));
  tearDown(() => AppStrings.manualLocale = null);

  testWidgets('DeviceListScreen renders correctly when empty', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and LAN indicator exist
    expect(find.text('Meine Kinder'), findsOneWidget);
    expect(find.text('LAN Local'), findsOneWidget);

    // Verify Empty state exists
    expect(find.text('Noch keine Kinder gekoppelt'), findsOneWidget);
    expect(find.text('Gerät koppeln'), findsOneWidget);
  });

  testWidgets('DeviceListScreen displays Online status with green indicator when device responds',
      (WidgetTester tester) async {
    final device = PairedDevice(
      id: 'tab-123',
      name: 'Felix Tablet',
      token: 'sec_123',
      localIpAddress: '192.168.1.150',
      port: 8085,
      lastSeen: DateTime.now(),
    );

    final mockRepo = MockPairingRepository(
      mockDevices: [device],
      isOnline: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceListScreen(repository: mockRepo),
      ),
    );

    // After async ping completes
    await tester.pumpAndSettle();

    expect(find.text('Felix Tablet'), findsOneWidget);
    expect(find.text('Online • LAN (192.168.1.150)'), findsOneWidget);
  });

  testWidgets('DeviceListScreen displays Offline status with red indicator when device does not respond',
      (WidgetTester tester) async {
    final device = PairedDevice(
      id: 'tab-456',
      name: 'Emma Tablet',
      token: 'sec_456',
      localIpAddress: '192.168.1.160',
      port: 8085,
      lastSeen: DateTime.now(),
    );

    final mockRepo = MockPairingRepository(
      mockDevices: [device],
      isOnline: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceListScreen(repository: mockRepo),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Emma Tablet'), findsOneWidget);
    expect(find.text('Offline • LAN (192.168.1.160)'), findsOneWidget);
  });

  testWidgets('DeviceListScreen displays Checking status in English before response arrives',
      (WidgetTester tester) async {
    AppStrings.manualLocale = const Locale('en');

    final device = PairedDevice(
      id: 'tab-789',
      name: 'Timmy Phone',
      token: 'sec_789',
      localIpAddress: '192.168.1.170',
      port: 8085,
      lastSeen: DateTime.now(),
    );

    final mockRepo = MockPairingRepository(
      mockDevices: [device],
      isOnline: true,
      delay: const Duration(seconds: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceListScreen(repository: mockRepo),
      ),
    );

    // Initial pump after loading devices, ping is still pending
    await tester.pump();

    expect(find.text('Checking • LAN (192.168.1.170)'), findsOneWidget);

    // Complete pending ping
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Online • LAN (192.168.1.170)'), findsOneWidget);
  });
}
