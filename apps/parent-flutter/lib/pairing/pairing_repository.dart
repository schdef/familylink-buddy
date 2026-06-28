import 'package:shared_preferences/shared_preferences.dart';

class PairedDevice {
  final String name;
  final String fcmToken; // FCM token of the child device
  final DateTime lastSeen;

  const PairedDevice({
    required this.name,
    required this.fcmToken,
    required this.lastSeen,
  });
}

class PairingRepository {
  static const _keyDeviceName = 'paired_device_name';
  static const _keyDeviceToken = 'paired_device_token';
  static const _keyLastSeen = 'paired_device_last_seen';

  Future<PairedDevice?> loadPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyDeviceToken);
    if (token == null || token.isEmpty) return null;
    return PairedDevice(
      name: prefs.getString(_keyDeviceName) ?? "Kind",
      fcmToken: token,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(_keyLastSeen) ?? 0,
      ),
    );
  }

  Future<void> savePairedDevice(PairedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceName, device.name);
    await prefs.setString(_keyDeviceToken, device.fcmToken);
    await prefs.setInt(_keyLastSeen, device.lastSeen.millisecondsSinceEpoch);
  }

  Future<void> clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceName);
    await prefs.remove(_keyDeviceToken);
    await prefs.remove(_keyLastSeen);
  }
}
