import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/pairing/pairing_repository.dart';

void main() {
  group('PairingRepository Tests', () {
    late PairingRepository repository;

    setUp(() {
      repository = PairingRepository();
      // Initialize SharedPreferences mock
      SharedPreferences.setMockInitialValues({});
    });

    test('Loads null when no device paired', () async {
      final device = await repository.loadPairedDevice();
      expect(device, isNull);
    });

    test('Saves and loads paired device successfully', () async {
      final lastSeen = DateTime.now();
      final device = PairedDevice(
        name: 'Felix Phone',
        fcmToken: 'mock-fcm-token-123',
        lastSeen: lastSeen,
      );

      await repository.savePairedDevice(device);

      final loaded = await repository.loadPairedDevice();
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Felix Phone');
      expect(loaded.fcmToken, 'mock-fcm-token-123');
      // Shared preferences stores milliseconds, check equality within millisecond precision
      expect(loaded.lastSeen.millisecondsSinceEpoch, lastSeen.millisecondsSinceEpoch);
    });

    test('Clears paired device successfully', () async {
      final device = PairedDevice(
        name: 'Felix Phone',
        fcmToken: 'mock-fcm-token-123',
        lastSeen: DateTime.now(),
      );

      await repository.savePairedDevice(device);
      var loaded = await repository.loadPairedDevice();
      expect(loaded, isNotNull);

      await repository.clearPairedDevice();
      loaded = await repository.loadPairedDevice();
      expect(loaded, isNull);
    });
  });
}
