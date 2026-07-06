import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
