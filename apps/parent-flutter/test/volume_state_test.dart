import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
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

  group('VolumeState Tests', () {
    test('Default values', () {
      const state = VolumeState();
      expect(state.mediaVolume, -1);
      expect(state.ringtoneVolume, -1);
      expect(state.alarmVolume, -1);
      expect(state.maxMediaVolume, 15);
      expect(state.maxRingtoneVolume, 15);
      expect(state.maxAlarmVolume, 15);
      expect(state.isMuted, false);
      expect(state.isMusicActive, false);
      expect(state.timestamp, null);
      expect(state.isKnown, false);
    });

    test('fromJson parsing', () {
      final json = {
        'mediaVolume': 5,
        'ringtoneVolume': 7,
        'alarmVolume': 10,
        'maxMediaVolume': 15,
        'maxRingtoneVolume': 15,
        'maxAlarmVolume': 15,
        'isMuted': false,
        'isMusicActive': true,
        'timestamp': 1680000000000,
      };

      final state = VolumeState.fromJson(json);
      expect(state.mediaVolume, 5);
      expect(state.ringtoneVolume, 7);
      expect(state.alarmVolume, 10);
      expect(state.isMuted, false);
      expect(state.isMusicActive, true);
      expect(state.timestamp, DateTime.fromMillisecondsSinceEpoch(1680000000000));
      expect(state.isKnown, true);
    });

    test('fromJson parses mediaTitle, mediaArtist, and mediaPackage', () {
      final json = {
        'mediaVolume': 8,
        'ringtoneVolume': 5,
        'alarmVolume': 5,
        'isMusicActive': true,
        'mediaTitle': 'Die Drei ??? Kids',
        'mediaArtist': 'Europa',
        'mediaPackage': 'com.spotify.music',
      };
      final state = VolumeState.fromJson(json);
      expect(state.mediaTitle, 'Die Drei ??? Kids');
      expect(state.mediaArtist, 'Europa');
      expect(state.mediaPackage, 'com.spotify.music');
    });

    test('fromJson parsing with nulls / missing values', () {
      final json = <String, dynamic>{};
      final state = VolumeState.fromJson(json);
      expect(state.mediaVolume, -1);
      expect(state.maxMediaVolume, 15);
      expect(state.isMuted, false);
      expect(state.isMusicActive, false);
      expect(state.timestamp, null);
    });

    test('copyWith updates isMusicActive and other properties', () {
      const original = VolumeState(
        mediaVolume: 3,
        ringtoneVolume: 4,
        alarmVolume: 5,
        isMusicActive: false,
      );

      final modified = original.copyWith(
        mediaVolume: 6,
        isMusicActive: true,
      );

      expect(modified.mediaVolume, 6);
      expect(modified.ringtoneVolume, 4);
      expect(modified.alarmVolume, 5);
      expect(modified.isMusicActive, true);
    });
  });

  group('VolumeRepository Direct Wi-Fi REST API Tests', () {
    test('setVolume attempts direct REST API and succeeds', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        final result = await repo.setVolume(
          childFcmToken: 'some_token',
          stream: 'MEDIA',
          level: 8,
        );

        expect(result, isTrue);
        expect(repo.volumeState.mediaVolume, 8);
        expect(repo.isConnected, isTrue);
      }, () => MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.100:8085/set_volume?stream=MEDIA&level=8');
        expect(request.headers['X-Buddy-Token'], 'some_token');
        expect(request.headers['Content-Type'], 'application/json');
        expect(jsonDecode(request.body), {'stream': 'MEDIA', 'level': 8});
        expect(request.method, 'POST');
        return http.Response(jsonEncode({'status': 'success'}), 200);
      }));
    });

    test('setVolume updates volumeState from response body when full state is returned', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        final result = await repo.setVolume(
          childFcmToken: 'some_token',
          stream: 'MEDIA',
          level: 10,
        );

        expect(result, isTrue);
        expect(repo.volumeState.mediaVolume, 10);
        expect(repo.volumeState.maxMediaVolume, 15);
        expect(repo.volumeState.ringtoneVolume, 7);
        expect(repo.volumeState.isMusicActive, false);
        expect(repo.isConnected, isTrue);
      }, () => MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.100:8085/set_volume?stream=MEDIA&level=10');
        expect(request.headers['X-Buddy-Token'], 'some_token');
        expect(request.headers['Content-Type'], 'application/json');
        return http.Response(
          jsonEncode({
            'status': 'success',
            'mediaVolume': 10,
            'maxMediaVolume': 15,
            'ringtoneVolume': 7,
            'maxRingtoneVolume': 15,
            'alarmVolume': 5,
            'maxAlarmVolume': 15,
            'isMuted': false,
            'isMusicActive': false,
          }),
          200,
        );
      }));
    });

    test('requestVolumeReport attempts direct REST API and succeeds with isMusicActive', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        await repo.requestVolumeReport('some_token');

        expect(repo.volumeState.mediaVolume, 5);
        expect(repo.volumeState.ringtoneVolume, 7);
        expect(repo.volumeState.isMusicActive, true);
        expect(repo.isConnected, isTrue);
      }, () => MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.100:8085/volume_report');
        expect(request.headers['X-Buddy-Token'], 'some_token');
        expect(request.method, 'GET');
        return http.Response(jsonEncode({
          'mediaVolume': 5,
          'ringtoneVolume': 7,
          'alarmVolume': 10,
          'maxMediaVolume': 15,
          'maxRingtoneVolume': 15,
          'maxAlarmVolume': 15,
          'isMuted': false,
          'isMusicActive': true,
        }), 200);
      }));
    });

    test('stopAudioPlayback sends stop_audio POST and clears isMusicActive on 200', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';
      repo.volumeStateForTesting = const VolumeState(
        mediaVolume: 8,
        isMusicActive: true,
      );

      await http.runWithClient(() async {
        final result = await repo.stopAudioPlayback(childToken: 'child_token_123');

        expect(result, isTrue);
        expect(repo.volumeState.isMusicActive, isFalse);
        expect(repo.isConnected, isTrue);
      }, () => MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.100:8085/stop_audio');
        expect(request.headers['X-Buddy-Token'], 'child_token_123');
        expect(request.method, 'POST');
        return http.Response(jsonEncode({'status': 'success', 'message': 'Audio stopped'}), 200);
      }));
    });

    test('stopAudioPlayback returns false when direct REST API fails', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';
      repo.volumeStateForTesting = const VolumeState(
        mediaVolume: 8,
        isMusicActive: true,
      );

      await http.runWithClient(() async {
        final result = await repo.stopAudioPlayback(childToken: 'child_token_123');

        expect(result, isFalse);
        expect(repo.volumeState.isMusicActive, isTrue);
      }, () => MockClient((request) async {
        return http.Response('Internal Error', 500);
      }));
    });

    test('setVolume returns false when direct REST API fails', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        final result = await repo.setVolume(
          childFcmToken: 'some_token',
          stream: 'MEDIA',
          level: 8,
        );

        expect(result, isFalse);
      }, () => MockClient((request) async {
        return http.Response('Error', 500);
      }));
    });

    test('requestVolumeReport handles error gracefully when direct REST API fails', () async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';

      await http.runWithClient(() async {
        await repo.requestVolumeReport('some_token');
        expect(repo.isConnected, isFalse);
      }, () => MockClient((request) async {
        return http.Response('Error', 500);
      }));
    });

    test('getLastSeenText formats correctly', () {
      final now = DateTime(2026, 7, 12, 12, 0, 0);

      // Null case
      expect(VolumeRepository.getLastSeenText(null, now: now), 'Keine Verbindungshistorie');

      // Seconds cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(seconds: 5)), now: now), 'Gerade eben aktiv');
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(seconds: 45)), now: now), 'Vor 45 Sek. aktiv');

      // Minutes cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(minutes: 5)), now: now), 'Vor 5 Min. aktiv');

      // Hours cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(hours: 3)), now: now), 'Vor 3 Std. aktiv');

      // Days cases
      expect(VolumeRepository.getLastSeenText(now.subtract(const Duration(days: 2)), now: now), 'Vor 2 Tagen aktiv');
    });
  });

  group('VolumeControlScreen Active Audio UI Tests', () {
    testWidgets('renders active audio card when isMusicActive is true and tapping stops playback', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('stop_audio')) {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response(jsonEncode({
          'mediaVolume': 10,
          'ringtoneVolume': 8,
          'alarmVolume': 12,
          'isMusicActive': true,
        }), 200);
      });

      final repo = VolumeRepository(httpClient: client);
      repo.localIpAddress = '192.168.1.100';
      repo.volumeStateForTesting = VolumeState(
        mediaVolume: 10,
        ringtoneVolume: 8,
        alarmVolume: 12,
        isMusicActive: true,
        timestamp: DateTime.now(),
      );

      final device = PairedDevice(
        id: 'dev-1',
        name: 'Kind-Tablet',
        token: 'token-abc',
        localIpAddress: '192.168.1.100',
        lastSeen: DateTime.now(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<VolumeRepository>.value(
          value: repo,
          child: MaterialApp(
            home: VolumeControlScreen(device: device),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Verify Active Audio Card is visible
      expect(find.byKey(const ValueKey('active_audio_card')), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
      expect(find.text('Audio wird wiedergegeben (z. B. Spotify)'), findsOneWidget);
      expect(find.text('Aktive Medienwiedergabe auf dem Tablet'), findsOneWidget);

      final stopButton = find.byKey(const ValueKey('stop_audio_button'));
      expect(stopButton, findsOneWidget);
      expect(find.text('Wiedergabe stoppen'), findsOneWidget);

      await tester.ensureVisible(stopButton);
      await tester.pumpAndSettle();

      // Tap "Wiedergabe stoppen"
      await tester.tap(stopButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify SnackBar shown and isMusicActive updated
      expect(find.text('Medienwiedergabe gestoppt.'), findsOneWidget);
      expect(repo.volumeState.isMusicActive, isFalse);
      expect(find.byKey(const ValueKey('active_audio_card')), findsNothing);
    });

    testWidgets('does not render active audio card when isMusicActive is false', (tester) async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';
      repo.volumeStateForTesting = VolumeState(
        mediaVolume: 5,
        ringtoneVolume: 5,
        alarmVolume: 5,
        isMusicActive: false,
        timestamp: DateTime.now(),
      );

      final device = PairedDevice(
        id: 'dev-1',
        name: 'Kind-Tablet',
        token: 'token-abc',
        localIpAddress: '192.168.1.100',
        lastSeen: DateTime.now(),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(
          ChangeNotifierProvider<VolumeRepository>.value(
            value: repo,
            child: MaterialApp(
              home: VolumeControlScreen(device: device),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('active_audio_card')), findsNothing);
        expect(find.text('Audio wird wiedergegeben (z. B. Spotify)'), findsNothing);
      }, () => MockClient((request) async {
        return http.Response(jsonEncode({
          'mediaVolume': 5,
          'ringtoneVolume': 5,
          'alarmVolume': 5,
          'isMusicActive': false,
        }), 200);
      }));
    });

    testWidgets('renders track title and artist when mediaTitle/mediaArtist available', (tester) async {
      final repo = VolumeRepository();
      repo.localIpAddress = '192.168.1.100';
      repo.volumeStateForTesting = VolumeState(
        mediaVolume: 8,
        ringtoneVolume: 5,
        alarmVolume: 5,
        isMusicActive: true,
        mediaTitle: 'Song Title 123',
        mediaArtist: 'Great Artist',
        timestamp: DateTime.now(),
      );

      final device = PairedDevice(
        id: 'dev-1',
        name: 'Kind-Tablet',
        token: 'token-abc',
        localIpAddress: '192.168.1.100',
        lastSeen: DateTime.now(),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(
          ChangeNotifierProvider<VolumeRepository>.value(
            value: repo,
            child: MaterialApp(
              home: VolumeControlScreen(device: device),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('active_audio_card')), findsOneWidget);
        expect(find.text('Song Title 123'), findsOneWidget);
        expect(find.textContaining('Great Artist'), findsOneWidget);

        // Verify Mute All exists and Max Volume does not exist
        expect(find.byKey(const ValueKey('btn_mute_all')), findsOneWidget);
        expect(find.text('Lautstärke 100%'), findsNothing);
        expect(find.text('Max Volume'), findsNothing);

        // Verify Add Kid button exists in AppBar
        expect(find.byKey(const ValueKey('btn_add_kid')), findsOneWidget);
      }, () => MockClient((request) async {
        return http.Response(jsonEncode({
          'mediaVolume': 8,
          'ringtoneVolume': 5,
          'alarmVolume': 5,
          'isMusicActive': true,
          'mediaTitle': 'Song Title 123',
          'mediaArtist': 'Great Artist',
        }), 200);
      }));
    });
  });
}
