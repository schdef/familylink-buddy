import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/updater/p2p_updater_service.dart';

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
          return 42; // Mock version code returned by native Android
        }
        if (methodCall.method == 'installApk') {
          return true; // Mock successful installation launch
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
}
