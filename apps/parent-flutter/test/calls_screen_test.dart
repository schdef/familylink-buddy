import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/comms/comms_models.dart';
import 'package:parent_app/comms/comms_repository.dart';
import 'package:parent_app/comms/calls_screen.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/l10n/app_strings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.manualLocale = const Locale('en');
  });

  tearDown(() {
    AppStrings.manualLocale = null;
  });

  final testDevice = PairedDevice(
    id: 'test_child_tablet',
    name: 'Emma Tablet',
    token: 'sec_test_token_123',
    localIpAddress: '192.168.1.150',
    port: 8085,
    lastSeen: DateTime.now(),
  );

  Widget createTestWidget({
    required CommsRepository commsRepo,
    PairedDevice? device,
    String? localIpAddress,
  }) {
    return ChangeNotifierProvider<CommsRepository>.value(
      value: commsRepo,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
        ),
        home: CallsScreen(
          device: device ?? testDevice,
          localIpAddress: localIpAddress,
        ),
      ),
    );
  }

  group('CallsScreen Widget Tests', () {
    testWidgets('renders empty state when no call records are present', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Call History'), findsOneWidget);
      expect(find.text('Emma Tablet'), findsOneWidget);
      expect(find.text('No call records found'), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_chip_all')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_chip_incoming')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_chip_outgoing')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_chip_missed')), findsOneWidget);
    });

    testWidgets('displays incoming, outgoing, and missed call records properly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final calls = [
        CallRecord(
          id: 'call_1',
          phoneNumber: '+15551234567',
          contactName: 'Grandma Rose',
          callType: CallType.incoming,
          timestamp: now.millisecondsSinceEpoch,
          durationSeconds: 145, // 2m 25s
        ),
        CallRecord(
          id: 'call_2',
          phoneNumber: '+15559876543',
          contactName: null,
          callType: CallType.outgoing,
          timestamp: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          durationSeconds: 30,
        ),
        CallRecord(
          id: 'call_3',
          phoneNumber: '+15550001111',
          contactName: 'School Bus Driver',
          callType: CallType.missed,
          timestamp: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
          durationSeconds: 0,
        ),
      ];

      // Pre-seed in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_calls_${testDevice.id}',
        jsonEncode(calls.map((c) => c.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // Verify contact names and phone numbers
      expect(find.text('Grandma Rose'), findsOneWidget);
      expect(find.text('+15551234567'), findsOneWidget);
      expect(find.text('2m 25s'), findsOneWidget);

      expect(find.text('+15559876543'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);

      expect(find.text('School Bus Driver'), findsOneWidget);
      expect(find.text('Missed'), findsWidgets);
    });

    testWidgets('filters calls when tapping filter chips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final calls = [
        CallRecord(
          id: 'call_in',
          phoneNumber: '+1111111111',
          contactName: 'Alice',
          callType: CallType.incoming,
          timestamp: now.millisecondsSinceEpoch,
          durationSeconds: 60,
        ),
        CallRecord(
          id: 'call_out',
          phoneNumber: '+2222222222',
          contactName: 'Bob',
          callType: CallType.outgoing,
          timestamp: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          durationSeconds: 90,
        ),
        CallRecord(
          id: 'call_miss',
          phoneNumber: '+3333333333',
          contactName: 'Charlie',
          callType: CallType.missed,
          timestamp: now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
          durationSeconds: 0,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_calls_${testDevice.id}',
        jsonEncode(calls.map((c) => c.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // All visible
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);

      // Filter: Incoming
      await tester.tap(find.byKey(const ValueKey('filter_chip_incoming')));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsNothing);

      // Filter: Outgoing
      await tester.tap(find.byKey(const ValueKey('filter_chip_outgoing')));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsNothing);

      // Filter: Missed
      await tester.tap(find.byKey(const ValueKey('filter_chip_missed')));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsOneWidget);

      // Filter: Back to All
      await tester.tap(find.byKey(const ValueKey('filter_chip_all')));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('search filters records by contact name or number', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final calls = [
        const CallRecord(
          id: 'c1',
          phoneNumber: '+15554443333',
          contactName: 'Doctor Office',
          callType: CallType.incoming,
          timestamp: 1000,
          durationSeconds: 120,
        ),
        const CallRecord(
          id: 'c2',
          phoneNumber: '+19998887777',
          contactName: 'Piano Teacher',
          callType: CallType.outgoing,
          timestamp: 2000,
          durationSeconds: 40,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_calls_${testDevice.id}',
        jsonEncode(calls.map((c) => c.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // Enter search term matching "Doctor"
      await tester.enterText(find.byKey(const ValueKey('calls_search_input')), 'Doctor');
      await tester.pumpAndSettle();

      expect(find.text('Doctor Office'), findsOneWidget);
      expect(find.text('Piano Teacher'), findsNothing);

      // Enter search term matching phone number "+1999"
      await tester.enterText(find.byKey(const ValueKey('calls_search_input')), '+1999');
      await tester.pumpAndSettle();

      expect(find.text('Doctor Office'), findsNothing);
      expect(find.text('Piano Teacher'), findsOneWidget);

      // Clear search
      await tester.enterText(find.byKey(const ValueKey('calls_search_input')), '');
      await tester.pumpAndSettle();

      expect(find.text('Doctor Office'), findsOneWidget);
      expect(find.text('Piano Teacher'), findsOneWidget);
    });

    testWidgets('sync button triggers LAN sync and displays success notification', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockClient = MockClient((request) async {
        if (request.url.path == '/call_logs') {
          return http.Response(
            jsonEncode([
              {
                'id': 'synced_call_1',
                'phoneNumber': '+18005550199',
                'contactName': 'Pediatrician',
                'callType': 'INCOMING',
                'timestamp': 1731666000000,
                'durationSeconds': 180,
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final repo = CommsRepository(httpClient: mockClient);
      await tester.pumpWidget(
        createTestWidget(
          commsRepo: repo,
          localIpAddress: '192.168.1.150',
        ),
      );
      await tester.pumpAndSettle();

      // Tap sync action button in AppBar
      final syncBtn = find.byKey(const ValueKey('calls_sync_button'));
      expect(syncBtn, findsOneWidget);
      await tester.tap(syncBtn);
      await tester.pumpAndSettle();

      expect(find.text('Logs synced successfully'), findsOneWidget);
      expect(find.text('Pediatrician'), findsOneWidget);
    });
  });
}
