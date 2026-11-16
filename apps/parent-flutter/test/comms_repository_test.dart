import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/comms/comms_models.dart';
import 'package:parent_app/comms/comms_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CommsRepository Cache & Persistence Tests', () {
    test('loadCache starts empty when no data in SharedPreferences', () async {
      final repo = CommsRepository();
      await repo.loadCache('device_1');

      expect(repo.calls, isEmpty);
      expect(repo.chats, isEmpty);
      expect(repo.lastSyncedAt, isNull);
      expect(repo.isLoading, isFalse);
      expect(repo.errorMessage, isNull);
    });

    test('loadCache populates calls and chats from SharedPreferences', () async {
      final callsJson = jsonEncode([
        {
          'id': 'call_1',
          'phoneNumber': '+4912345678',
          'contactName': 'Grandpa',
          'callType': 'INCOMING',
          'timestamp': 1000,
          'durationSeconds': 60,
        },
      ]);
      final chatsJson = jsonEncode([
        {
          'id': 'chat_1',
          'appPackage': 'com.whatsapp',
          'appName': 'WhatsApp',
          'senderOrChat': 'Grandpa',
          'text': 'How are you?',
          'isOutgoing': false,
          'timestamp': 2000,
        },
      ]);

      SharedPreferences.setMockInitialValues({
        'comms_calls_device_1': callsJson,
        'comms_chats_device_1': chatsJson,
        'comms_last_synced_device_1': 1731665000000,
      });

      final repo = CommsRepository();
      await repo.loadCache('device_1');

      expect(repo.calls.length, 1);
      expect(repo.calls.first.id, 'call_1');
      expect(repo.calls.first.contactName, 'Grandpa');

      expect(repo.chats.length, 1);
      expect(repo.chats.first.id, 'chat_1');
      expect(repo.chats.first.text, 'How are you?');

      expect(repo.lastSyncedAt?.millisecondsSinceEpoch, 1731665000000);
    });

    test('clearCache wipes in-memory lists and SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'comms_calls_device_1': '[{}]',
        'comms_chats_device_1': '[{}]',
        'comms_last_synced_device_1': 1000,
      });

      final repo = CommsRepository();
      await repo.clearCache('device_1');

      expect(repo.calls, isEmpty);
      expect(repo.chats, isEmpty);
      expect(repo.lastSyncedAt, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('comms_calls_device_1'), isFalse);
      expect(prefs.containsKey('comms_chats_device_1'), isFalse);
      expect(prefs.containsKey('comms_last_synced_device_1'), isFalse);
    });

    test('pruneOldRecords truncates records exceeding maxCount', () async {
      final repo = CommsRepository();
      final mockCalls = List.generate(
        10,
        (i) => CallRecord(
          id: 'c_$i',
          phoneNumber: '123',
          callType: CallType.incoming,
          timestamp: i,
          durationSeconds: 10,
        ),
      );
      final mockChats = List.generate(
        10,
        (i) => ChatMessageRecord(
          id: 'm_$i',
          appPackage: 'com.whatsapp',
          appName: 'WhatsApp',
          senderOrChat: 'Friend',
          text: 'msg $i',
          isOutgoing: false,
          timestamp: i,
        ),
      );

      // Pre-seed in prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comms_calls_dev',
        jsonEncode(mockCalls.map((c) => c.toJson()).toList()),
      );
      await prefs.setString(
        'comms_chats_dev',
        jsonEncode(mockChats.map((c) => c.toJson()).toList()),
      );

      await repo.loadCache('dev');
      expect(repo.calls.length, 10);
      expect(repo.chats.length, 10);

      await repo.pruneOldRecords('dev', maxCount: 4);

      expect(repo.calls.length, 4);
      expect(repo.chats.length, 4);
    });
  });

  group('CommsRepository syncLogs Tests', () {
    test('syncLogs calls /call_logs and /chat_logs with token and persists', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['X-Buddy-Token'], 'test_secret_token');

        if (request.url.path == '/call_logs') {
          expect(request.url.queryParameters['since'], '0');
          return http.Response(
            jsonEncode({
              'success': true,
              'records': [
                {
                  'id': 'call_incoming_1',
                  'phoneNumber': '+49170111111',
                  'contactName': 'School Office',
                  'callType': 'INCOMING',
                  'timestamp': 1731664000000,
                  'durationSeconds': 95,
                },
              ],
            }),
            200,
          );
        } else if (request.url.path == '/chat_logs') {
          expect(request.url.queryParameters['since'], '0');
          return http.Response(
            jsonEncode([
              {
                'id': 'msg_wa_1',
                'appPackage': 'com.whatsapp',
                'appName': 'WhatsApp',
                'senderOrChat': 'Class 4b',
                'text': 'Math test postponed!',
                'isOutgoing': false,
                'timestamp': 1731664100000,
              },
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final repo = CommsRepository(httpClient: mockClient);
      final result = await repo.syncLogs(
        '192.168.1.50',
        'test_secret_token',
        'tablet_123',
      );

      expect(result, isTrue);
      expect(repo.isLoading, isFalse);
      expect(repo.errorMessage, isNull);
      expect(repo.calls.length, 1);
      expect(repo.calls.first.contactName, 'School Office');
      expect(repo.chats.length, 1);
      expect(repo.chats.first.text, 'Math test postponed!');
      expect(repo.lastSyncedAt, isNotNull);

      // Verify persistence by loading into a separate repository instance
      final repo2 = CommsRepository();
      await repo2.loadCache('tablet_123');
      expect(repo2.calls.length, 1);
      expect(repo2.chats.length, 1);
    });

    test('syncLogs deduplicates records by ID and sorts descending', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/call_logs') {
          return http.Response(
            jsonEncode([
              {
                'id': 'c_1',
                'phoneNumber': '111',
                'callType': 'INCOMING',
                'timestamp': 1000,
                'durationSeconds': 10,
              },
              {
                'id': 'c_2',
                'phoneNumber': '222',
                'callType': 'OUTGOING',
                'timestamp': 3000, // Newer
                'durationSeconds': 20,
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final repo = CommsRepository(httpClient: mockClient);
      await repo.syncLogs('192.168.1.50', 'token', 'dev');

      expect(repo.calls.length, 2);
      expect(repo.calls[0].id, 'c_2'); // Newest first
      expect(repo.calls[1].id, 'c_1');

      // Sync again with updated duration for c_1 and a new c_3
      final mockClient2 = MockClient((request) async {
        if (request.url.path == '/call_logs') {
          return http.Response(
            jsonEncode([
              {
                'id': 'c_1',
                'phoneNumber': '111',
                'callType': 'INCOMING',
                'timestamp': 1000,
                'durationSeconds': 45, // Updated
              },
              {
                'id': 'c_3',
                'phoneNumber': '333',
                'callType': 'MISSED',
                'timestamp': 5000, // Brand new, newest
                'durationSeconds': 0,
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await repo.syncLogs('192.168.1.50', 'token', 'dev', client: mockClient2);

      // Should have 3 unique items total: c_3, c_2, c_1
      expect(repo.calls.length, 3);
      expect(repo.calls[0].id, 'c_3');
      expect(repo.calls[1].id, 'c_2');
      expect(repo.calls[2].id, 'c_1');
      expect(repo.calls[2].durationSeconds, 45); // Updated duration preserved
    });

    test('syncLogs sets errorMessage and returns false on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final repo = CommsRepository(httpClient: mockClient);
      final result = await repo.syncLogs('192.168.1.50', 'bad_token', 'dev');

      expect(result, isFalse);
      expect(repo.isLoading, isFalse);
      expect(repo.errorMessage, contains('401'));
    });
  });
}
