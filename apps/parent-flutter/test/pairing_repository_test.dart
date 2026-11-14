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

    test('Multi-kid support: saves multiple devices, loads all, updates and removes', () async {
      final dev1 = PairedDevice(
        id: 'tablet-felix',
        name: 'Felix Tablet',
        token: 'token-felix-111',
        lastSeen: DateTime.now(),
      );
      final dev2 = PairedDevice(
        id: 'tablet-sarah',
        name: 'Sarah Tablet',
        token: 'token-sarah-222',
        lastSeen: DateTime.now(),
      );

      await repository.savePairedDevice(dev1);
      await repository.savePairedDevice(dev2);

      final all = await repository.loadAllPairedDevices();
      expect(all.length, 2);
      expect(all[0].id, 'tablet-felix');
      expect(all[1].id, 'tablet-sarah');

      // Update dev1 name
      final dev1Updated = dev1.copyWith(name: 'Felix Big Tablet');
      await repository.savePairedDevice(dev1Updated);
      final updatedAll = await repository.loadAllPairedDevices();
      expect(updatedAll.length, 2);
      expect(updatedAll[0].name, 'Felix Big Tablet');

      // Remove dev1
      await repository.removePairedDevice(dev1.id);
      final remaining = await repository.loadAllPairedDevices();
      expect(remaining.length, 1);
      expect(remaining[0].id, 'tablet-sarah');

      // Verify active primary device fallback
      final active = await repository.loadPairedDevice();
      expect(active, isNotNull);
      expect(active!.id, 'tablet-sarah');
    });

    test('Loads legacy single-device key seamlessly in loadAllPairedDevices', () async {
      SharedPreferences.setMockInitialValues({
        'paired_device_name': 'Legacy Tablet',
        'paired_device_token': 'legacy-token-999',
        'paired_device_last_seen': DateTime.now().millisecondsSinceEpoch,
      });

      final all = await repository.loadAllPairedDevices();
      expect(all.length, 1);
      expect(all.first.name, 'Legacy Tablet');
      expect(all.first.token, 'legacy-token-999');
    });
  });
}
