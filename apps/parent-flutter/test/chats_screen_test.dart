import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/comms/comms_models.dart';
import 'package:parent_app/comms/comms_repository.dart';
import 'package:parent_app/comms/chats_screen.dart';
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
    name: 'Ben Tablet',
    token: 'sec_test_token_456',
    localIpAddress: '192.168.1.160',
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
        home: ChatsScreen(
          device: device ?? testDevice,
          localIpAddress: localIpAddress,
        ),
      ),
    );
  }

  group('ChatsScreen Widget Tests', () {
    testWidgets('renders empty state when no chats are cached', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Chat Messages'), findsOneWidget);
      expect(find.text('Ben Tablet'), findsOneWidget);
      expect(find.text('No chat messages found'), findsOneWidget);
      expect(find.byKey(const ValueKey('app_filter_all')), findsOneWidget);
      expect(find.byKey(const ValueKey('app_filter_whatsapp')), findsOneWidget);
      expect(find.byKey(const ValueKey('app_filter_sms')), findsOneWidget);
      expect(find.byKey(const ValueKey('app_filter_telegram')), findsOneWidget);
      expect(find.byKey(const ValueKey('app_filter_signal')), findsOneWidget);
    });

    testWidgets('renders conversation threads grouped with badges and snippets', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final messages = [
        ChatMessageRecord(
          id: 'msg_1',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Lucas',
          text: 'Are we doing homework today?',
          isOutgoing: false,
          timestamp: now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'msg_2',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Lucas',
          text: 'Yes, after football practice!',
          isOutgoing: true,
          timestamp: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'msg_3',
          appPackage: 'com.google.android.apps.messaging',
          appName: 'Messages',
          senderOrChat: 'Tennis Coach',
          text: 'Match starts at 4 PM.',
          isOutgoing: false,
          timestamp: now.millisecondsSinceEpoch,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_chats_${testDevice.id}',
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // Thread titles
      expect(find.text('Lucas'), findsOneWidget);
      expect(find.text('Tennis Coach'), findsOneWidget);

      // Latest message previews
      expect(find.text('You: Yes, after football practice!'), findsOneWidget);
      expect(find.text('Match starts at 4 PM.'), findsOneWidget);

      // Badges
      expect(find.text('WhatsApp'), findsWidgets);
      expect(find.text('SMS / Messages'), findsWidgets);
    });

    testWidgets('app filter chips filter conversation threads', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final messages = [
        ChatMessageRecord(
          id: 'wa_1',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Family Group',
          text: 'Sunday picnic at noon',
          isOutgoing: false,
          timestamp: now.millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'sms_1',
          appPackage: 'com.google.android.apps.messaging',
          appName: 'Messages',
          senderOrChat: 'Dentist',
          text: 'Appointment reminder for tomorrow',
          isOutgoing: false,
          timestamp: now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'tg_1',
          appPackage: 'org.telegram.messenger',
          appName: 'Telegram',
          senderOrChat: 'Chess Club',
          text: 'Tournament brackets posted',
          isOutgoing: false,
          timestamp: now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_chats_${testDevice.id}',
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // All visible
      expect(find.text('Family Group'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('Chess Club'), findsOneWidget);

      // Filter: WhatsApp
      await tester.tap(find.byKey(const ValueKey('app_filter_whatsapp')));
      await tester.pumpAndSettle();

      expect(find.text('Family Group'), findsOneWidget);
      expect(find.text('Dentist'), findsNothing);
      expect(find.text('Chess Club'), findsNothing);

      // Filter: SMS
      await tester.tap(find.byKey(const ValueKey('app_filter_sms')));
      await tester.pumpAndSettle();

      expect(find.text('Family Group'), findsNothing);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('Chess Club'), findsNothing);

      // Filter: Telegram
      await tester.tap(find.byKey(const ValueKey('app_filter_telegram')));
      await tester.pumpAndSettle();

      expect(find.text('Family Group'), findsNothing);
      expect(find.text('Dentist'), findsNothing);
      expect(find.text('Chess Club'), findsOneWidget);

      // Filter: Back to All
      await tester.tap(find.byKey(const ValueKey('app_filter_all')));
      await tester.pumpAndSettle();

      expect(find.text('Family Group'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('Chess Club'), findsOneWidget);
    });

    testWidgets('search bar filters by contact or message text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final messages = [
        const ChatMessageRecord(
          id: 'm1',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Math Tutor',
          text: 'Practice calculus chapter 3',
          isOutgoing: false,
          timestamp: 1000,
        ),
        const ChatMessageRecord(
          id: 'm2',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Best Friend',
          text: 'Wanna play Minecraft?',
          isOutgoing: false,
          timestamp: 2000,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_chats_${testDevice.id}',
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // Search by contact name "Tutor"
      await tester.enterText(find.byKey(const ValueKey('chats_search_input')), 'Tutor');
      await tester.pumpAndSettle();

      expect(find.text('Math Tutor'), findsOneWidget);
      expect(find.text('Best Friend'), findsNothing);

      // Search by message body "Minecraft"
      await tester.enterText(find.byKey(const ValueKey('chats_search_input')), 'Minecraft');
      await tester.pumpAndSettle();

      expect(find.text('Math Tutor'), findsNothing);
      expect(find.text('Best Friend'), findsOneWidget);
    });

    testWidgets('tapping a thread navigates to ChatConversationDetailScreen with timeline bubbles', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final messages = [
        ChatMessageRecord(
          id: 'msg_in',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Grandpa',
          text: 'Did you get the birthday gift?',
          isOutgoing: false,
          timestamp: now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        ),
        ChatMessageRecord(
          id: 'msg_out',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Grandpa',
          text: 'Yes! Thank you so much Grandpa ❤️',
          isOutgoing: true,
          timestamp: now.millisecondsSinceEpoch,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_chats_${testDevice.id}',
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final repo = CommsRepository();
      await tester.pumpWidget(createTestWidget(commsRepo: repo));
      await tester.pumpAndSettle();

      // Tap thread card
      final threadCard = find.byKey(const ValueKey('chat_thread_item_com.whatsapp:::Grandpa'));
      expect(threadCard, findsOneWidget);
      await tester.tap(threadCard);
      await tester.pumpAndSettle();

      // Should be in detail screen
      expect(find.text('Did you get the birthday gift?'), findsOneWidget);
      expect(find.text('Yes! Thank you so much Grandpa ❤️'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_bubble_msg_in')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_bubble_msg_out')), findsOneWidget);
      expect(find.textContaining('2 messages'), findsOneWidget);

      // Pop back
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Chat Messages'), findsOneWidget);
    });

    testWidgets('sync button triggers LAN chat sync and displays SnackBar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockClient = MockClient((request) async {
        if (request.url.path == '/chat_logs') {
          return http.Response(
            jsonEncode([
              {
                'id': 'synced_msg_1',
                'appPackage': 'com.whatsapp',
                'appName': 'WhatsApp',
                'senderOrChat': 'Soccer Team',
                'text': 'Practice at 5 PM on Tuesday',
                'isOutgoing': false,
                'timestamp': 1731667000000,
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
          localIpAddress: '192.168.1.160',
        ),
      );
      await tester.pumpAndSettle();

      final syncBtn = find.byKey(const ValueKey('chats_sync_button'));
      expect(syncBtn, findsOneWidget);
      await tester.tap(syncBtn);
      await tester.pumpAndSettle();

      expect(find.text('Logs synced successfully'), findsOneWidget);
      expect(find.text('Soccer Team'), findsOneWidget);
    });
  });
}
