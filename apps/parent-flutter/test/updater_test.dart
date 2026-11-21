import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/updater/p2p_updater_service.dart';
import 'package:parent_app/updater/updater_service.dart';
import 'package:parent_app/updater/update_dialog.dart';
import 'package:parent_app/l10n/app_strings.dart';

void main() {
  const MethodChannel channel = MethodChannel('com.familylink.buddy.parent/updater');

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Parent App Auto-Updater Platform Channel Tests', () {
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'getAppVersionCode') {
          return 42;
        }
        if (methodCall.method == 'installApk') {
          return true;
        }
        if (methodCall.method == 'pickApkFile') {
          return {
            'path': '/data/user/0/com.familylink.buddy.parent/cache/picked_child-app-release.apk',
            'name': 'child-app-release.apk',
            'size': 28000000,
          };
        }
        return null;
      });
    });

    tearDown(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getAppVersionCode channel invocation returns correct mocked code', () async {
      final int version = await channel.invokeMethod('getAppVersionCode');
      
      expect(version, 42);
      expect(log, hasLength(1));
      expect(log.first.method, 'getAppVersionCode');
    });

    test('installApk channel invocation passes correct path argument', () async {
      final bool result = await channel.invokeMethod('installApk', {
        'filePath': '/dummy/path/to/update.apk',
      });

      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'installApk');
      expect(log.first.arguments['filePath'], '/dummy/path/to/update.apk');
    });

    test('pickApkFile channel invocation returns path, name and size', () async {
      final Map<dynamic, dynamic>? result = await channel.invokeMethod('pickApkFile');

      expect(result, isNotNull);
      expect(result!['path'], contains('picked_child-app-release.apk'));
      expect(result['name'], 'child-app-release.apk');
      expect(result['size'], 28000000);
      expect(log, hasLength(1));
      expect(log.first.method, 'pickApkFile');
    });

    test('P2PUpdaterService.pickApkFile invokes channel and parses map', () async {
      final service = P2PUpdaterService();
      final result = await service.pickApkFile();

      expect(result, isNotNull);
      expect(result!['path'], contains('picked_child-app-release.apk'));
      expect(result['name'], 'child-app-release.apk');
      expect(result['size'], 28000000);
      expect(log, hasLength(1));
      expect(log.first.method, 'pickApkFile');
    });

    test('P2PUpdaterService.pickApkFile returns null when picker cancelled', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return null;
      });

      final service = P2PUpdaterService();
      final result = await service.pickApkFile();

      expect(result, isNull);
    });
  });

  group('ReleaseInfo Data Model Tests', () {
    test('ReleaseInfo.fromJson parses complete GitHub release payload with assets', () {
      final json = {
        'tag_name': 'v1.2.0',
        'body': 'Exciting new features and bug fixes!',
        'html_url': 'https://github.com/schdef/familylink-buddy/releases/tag/v1.2.0',
        'assets': [
          {
            'name': 'parent-app-release.apk',
            'browser_download_url': 'https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/parent-app-release.apk'
          },
          {
            'name': 'child-app-release.apk',
            'browser_download_url': 'https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/child-app-release.apk'
          }
        ]
      };

      final info = ReleaseInfo.fromJson(json);

      expect(info.tagName, 'v1.2.0');
      expect(info.releaseNotes, 'Exciting new features and bug fixes!');
      expect(info.parentApkUrl, 'https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/parent-app-release.apk');
      expect(info.childApkUrl, 'https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/child-app-release.apk');
      expect(info.htmlUrl, 'https://github.com/schdef/familylink-buddy/releases/tag/v1.2.0');
    });

    test('ReleaseInfo.fromJson falls back to raw github URLs when assets missing', () {
      final json = {
        'tag_name': 'v1.1.2',
        'body': 'Initial release',
        'html_url': 'https://github.com/schdef/familylink-buddy/releases',
        'assets': <dynamic>[]
      };

      final info = ReleaseInfo.fromJson(json);

      expect(info.tagName, 'v1.1.2');
      expect(info.parentApkUrl, 'https://raw.githubusercontent.com/schdef/familylink-buddy/main/build/parent-app-release.apk');
      expect(info.childApkUrl, 'https://raw.githubusercontent.com/schdef/familylink-buddy/main/build/child-app-release.apk');
    });
  });

  group('UpdaterService Logic & Comparison Tests', () {
    test('isNewerVersion correctly evaluates version numbers', () {
      expect(UpdaterService.isNewerVersion('v1.2.0', '1.1.2'), isTrue);
      expect(UpdaterService.isNewerVersion('v1.1.3', '1.1.2'), isTrue);
      expect(UpdaterService.isNewerVersion('v2.0.0', '1.1.2'), isTrue);
      expect(UpdaterService.isNewerVersion('1.1.2', '1.1.2'), isFalse);
      expect(UpdaterService.isNewerVersion('v1.1.2', '1.1.2'), isFalse);
      expect(UpdaterService.isNewerVersion('v1.1.1', '1.1.2'), isFalse);
      expect(UpdaterService.isNewerVersion('v1.0.9', '1.1.2'), isFalse);
    });

    test('fetchLatestRelease returns ReleaseInfo on HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/releases/latest'));
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.3.0',
            'body': 'Version 1.3.0 release notes',
            'html_url': 'https://github.com/schdef/familylink-buddy/releases/tag/v1.3.0',
            'assets': [
              {
                'name': 'parent-app-release.apk',
                'browser_download_url': 'https://example.com/parent.apk',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final info = await UpdaterService.fetchLatestRelease(client: mockClient);

      expect(info, isNotNull);
      expect(info!.tagName, 'v1.3.0');
      expect(info.releaseNotes, 'Version 1.3.0 release notes');
      expect(info.parentApkUrl, 'https://example.com/parent.apk');
    });

    test('fetchLatestRelease returns null on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final info = await UpdaterService.fetchLatestRelease(client: mockClient);
      expect(info, isNull);
    });

    test('downloadAndInstallParentApk streams file and invokes installApk', () async {
      final List<double> progressLog = [];
      final apkBytes = utf8.encode('DUMMY_APK_BINARY_CONTENT');

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          apkBytes,
          200,
          headers: {
            'content-length': apkBytes.length.toString(),
            'content-type': 'application/vnd.android.package-archive',
          },
        );
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'installApk') {
          return true;
        }
        return null;
      });

      final success = await UpdaterService.downloadAndInstallParentApk(
        apkUrl: 'https://example.com/parent.apk',
        onProgress: (p) => progressLog.add(p),
        client: mockClient,
      );

      expect(success, isTrue);
      expect(progressLog, isNotEmpty);
      expect(progressLog.first, 0.0);
      expect(progressLog.last, 1.0);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('downloadChildApk streams file and returns valid file path', () async {
      final List<double> progressLog = [];
      final apkBytes = utf8.encode('DUMMY_CHILD_APK_CONTENT');

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          apkBytes,
          200,
          headers: {
            'content-length': apkBytes.length.toString(),
          },
        );
      });

      final path = await UpdaterService.downloadChildApk(
        apkUrl: 'https://example.com/child.apk',
        onProgress: (p) => progressLog.add(p),
        client: mockClient,
      );

      expect(path, isNotNull);
      expect(path, contains('child-update.apk'));
      expect(progressLog, isNotEmpty);
      expect(progressLog.last, 1.0);
    });
  });

  group('UpdateDialog Widget Tests', () {
    setUp(() {
      AppStrings.manualLocale = const Locale('en');
    });

    tearDown(() {
      AppStrings.manualLocale = null;
    });

    testWidgets('Renders UpdateDialog and displays release information', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.2.0',
              'body': 'Cool updates are here!',
              'html_url': 'https://github.com/schdef/familylink-buddy/releases',
              'assets': [
                {
                  'name': 'parent-app-release.apk',
                  'browser_download_url': 'https://example.com/parent.apk',
                },
                {
                  'name': 'child-app-release.apk',
                  'browser_download_url': 'https://example.com/child.apk',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(utf8.encode('APK_DATA'), 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDialog(
              childIp: '192.168.1.150',
              client: mockClient,
            ),
          ),
        ),
      );

      // Initially shows checking
      expect(find.text('App Updates'), findsOneWidget);
      await tester.pumpAndSettle();

      // Shows release notes and version
      expect(find.text('Cool updates are here!'), findsOneWidget);
      expect(find.textContaining('v1.2.0'), findsWidgets);
      expect(find.byKey(const ValueKey('btn_update_parent_app')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_update_child_app')), findsOneWidget);
    });

    testWidgets('Tapping Update Parent App triggers download and installation', (tester) async {
      bool installCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'installApk') {
          installCalled = true;
          return true;
        }
        return null;
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.2.0',
              'body': 'New features',
              'html_url': 'https://github.com/schdef/familylink-buddy/releases',
              'assets': [
                {
                  'name': 'parent-app-release.apk',
                  'browser_download_url': 'https://example.com/parent.apk',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(
          utf8.encode('APK_BYTES'),
          200,
          headers: {'content-length': '9'},
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDialog(
              childIp: '192.168.1.150',
              client: mockClient,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('btn_update_parent_app')));
        int waited = 0;
        while (!installCalled && waited < 20) {
          await Future.delayed(const Duration(milliseconds: 50));
          waited++;
        }
      });
      await tester.pumpAndSettle();

      expect(installCalled, isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}
