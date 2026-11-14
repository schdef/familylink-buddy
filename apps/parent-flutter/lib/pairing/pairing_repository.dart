import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PairedDevice {
  final String id;
  final String name;
  final String token; // Token or LAN identifier
  final String? localIpAddress;
  final int port;
  final DateTime lastSeen;

  const PairedDevice({
    String? id,
    required this.name,
    String? token,
    String? fcmToken,
    String? localIpAddress,
    String? ipAddress,
    this.port = 8085,
    required this.lastSeen,
  })  : id = (id != null && id != '') ? id : (token ?? fcmToken ?? ''),
        token = token ?? fcmToken ?? '',
        localIpAddress = localIpAddress ?? ipAddress;

  // Backwards compatibility getters
  String get fcmToken => token;
  String get deviceId => id;
  String? get ipAddress => localIpAddress;

  PairedDevice copyWith({
    String? id,
    String? name,
    String? token,
    String? localIpAddress,
    int? port,
    DateTime? lastSeen,
  }) {
    return PairedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      token: token ?? this.token,
      localIpAddress: localIpAddress ?? this.localIpAddress,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'token': token,
    'fcmToken': token,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'localIpAddress': localIpAddress,
    'ipAddress': localIpAddress,
    'port': port,
  };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Kind',
    token: json['token'] as String? ?? json['fcmToken'] as String? ?? '',
    fcmToken: json['fcmToken'] as String?,
    lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int? ?? 0),
    localIpAddress: json['localIpAddress'] as String? ?? json['ipAddress'] as String?,
    ipAddress: json['ipAddress'] as String?,
    port: json['port'] as int? ?? 8085,
  );
}

class PairingQrPayload {
  final int version;
  final String deviceId;
  final String deviceName;
  final String ip;
  final int port;
  final String token;

  const PairingQrPayload({
    this.version = 1,
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    this.port = 8085,
    required this.token,
  });

  static (String, int) extractHostAndPort(String input, {int defaultPort = 8085}) {
    var clean = input.trim();
    if (clean.startsWith('http://')) {
      clean = clean.substring(7);
    } else if (clean.startsWith('https://')) {
      clean = clean.substring(8);
    }
    // Remove query params if any
    final queryIndex = clean.indexOf('?');
    if (queryIndex != -1) {
      clean = clean.substring(0, queryIndex);
    }
    // Remove path if any
    final slashIndex = clean.indexOf('/');
    if (slashIndex != -1) {
      clean = clean.substring(0, slashIndex);
    }
    clean = clean.trim();

    int port = defaultPort;
    String host = clean;
    if (clean.contains(':')) {
      final parts = clean.split(':');
      host = parts[0].trim();
      if (parts.length > 1) {
        final parsedPort = int.tryParse(parts[1].trim());
        if (parsedPort != null && parsedPort > 0 && parsedPort <= 65535) {
          port = parsedPort;
        }
      }
    }
    return (host, port);
  }

  static bool isIpAddress(String str) {
    final clean = str.trim().toLowerCase();
    if (clean == 'emulator' || clean == 'localhost') return true;
    final parts = clean.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static PairingQrPayload? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        final deviceId = map['deviceId'] as String? ?? map['id'] as String? ?? '';
        final deviceName = map['deviceName'] as String? ?? map['name'] as String? ?? 'Kind';
        var rawIp = map['ip'] as String? ?? map['ipAddress'] as String? ?? '';
        var rawPort = map['port'] is int
            ? map['port'] as int
            : (map['port'] is String ? int.tryParse(map['port'] as String) ?? 8085 : 8085);

        if (rawIp.isNotEmpty) {
          final (h, p) = extractHostAndPort(rawIp, defaultPort: rawPort);
          rawIp = h;
          rawPort = p;
        }

        final token = map['token'] as String? ?? map['fcmToken'] as String? ?? '';
        final version = map['v'] as int? ?? 1;

        return PairingQrPayload(
          version: version,
          deviceId: deviceId.isNotEmpty ? deviceId : token,
          deviceName: deviceName.isNotEmpty ? deviceName : 'Kind',
          ip: rawIp,
          port: rawPort,
          token: token,
        );
      } catch (_) {
        // Fallback to text parsing
      }
    }

    // Backwards compatibility for plain token/IP strings
    final (host, port) = extractHostAndPort(trimmed);

    if (isIpAddress(host) || host.contains('.')) {
      return PairingQrPayload(
        version: 1,
        deviceId: host,
        deviceName: 'Kind',
        ip: host,
        port: port,
        token: host,
      );
    }

    return PairingQrPayload(
      version: 1,
      deviceId: trimmed,
      deviceName: 'Kind',
      ip: '',
      port: 8085,
      token: trimmed,
    );
  }
}

class PairingRepository {
  static const _keyDeviceId = 'paired_device_id';
  static const _keyDeviceName = 'paired_device_name';
  static const _keyDeviceToken = 'paired_device_token';
  static const _keyLastSeen = 'paired_device_last_seen';
  static const _keyDeviceIp = 'paired_device_ip';
  static const _keyDevicePort = 'paired_device_port';
  static const _keyDevicesList = 'paired_devices_list';

  Future<PairedDevice?> loadPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final single = _loadSinglePairedDevice(prefs);
    if (single != null) return single;
    final list = await loadAllPairedDevices();
    return list.isNotEmpty ? list.first : null;
  }

  PairedDevice? _loadSinglePairedDevice(SharedPreferences prefs) {
    final token = prefs.getString(_keyDeviceToken);
    if (token == null || token.isEmpty) return null;
    return PairedDevice(
      id: prefs.getString(_keyDeviceId) ?? token,
      name: prefs.getString(_keyDeviceName) ?? "Kind",
      token: token,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(_keyLastSeen) ?? 0,
      ),
      localIpAddress: prefs.getString(_keyDeviceIp),
      port: prefs.getInt(_keyDevicePort) ?? 8085,
    );
  }

  Future<List<PairedDevice>> loadAllPairedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_keyDevicesList);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          final list = decoded
              .map((e) => PairedDevice.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    final single = _loadSinglePairedDevice(prefs);
    if (single != null) {
      return [single];
    }
    return [];
  }

  Future<List<PairedDevice>> loadPairedDevices() => loadAllPairedDevices();

  Future<void> savePairedDevice(PairedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceId, device.id);
    await prefs.setString(_keyDeviceName, device.name);
    await prefs.setString(_keyDeviceToken, device.token);
    await prefs.setInt(_keyLastSeen, device.lastSeen.millisecondsSinceEpoch);
    if (device.localIpAddress != null && device.localIpAddress!.isNotEmpty) {
      await prefs.setString(_keyDeviceIp, device.localIpAddress!);
    } else {
      await prefs.remove(_keyDeviceIp);
    }
    await prefs.setInt(_keyDevicePort, device.port);

    final devices = await loadAllPairedDevices();
    final index = devices.indexWhere((d) => d.id == device.id || d.token == device.token);
    if (index >= 0) {
      devices[index] = device;
    } else {
      devices.add(device);
    }
    await prefs.setString(
      _keyDevicesList,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> removePairedDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await loadAllPairedDevices();
    devices.removeWhere((d) => d.id == deviceId || d.token == deviceId);

    if (devices.isNotEmpty) {
      await prefs.setString(
        _keyDevicesList,
        jsonEncode(devices.map((d) => d.toJson()).toList()),
      );
      final currentToken = prefs.getString(_keyDeviceToken);
      final currentId = prefs.getString(_keyDeviceId);
      if (currentId == deviceId || currentToken == deviceId) {
        final first = devices.first;
        await prefs.setString(_keyDeviceId, first.id);
        await prefs.setString(_keyDeviceName, first.name);
        await prefs.setString(_keyDeviceToken, first.token);
        await prefs.setInt(_keyLastSeen, first.lastSeen.millisecondsSinceEpoch);
        if (first.localIpAddress != null && first.localIpAddress!.isNotEmpty) {
          await prefs.setString(_keyDeviceIp, first.localIpAddress!);
        } else {
          await prefs.remove(_keyDeviceIp);
        }
        await prefs.setInt(_keyDevicePort, first.port);
      }
    } else {
      await clearPairedDevice();
    }
  }

  Future<void> updateDeviceIp(String newIp, {int? port}) async {
    final current = await loadPairedDevice();
    if (current != null) {
      final updated = current.copyWith(
        localIpAddress: newIp,
        port: port ?? current.port,
        lastSeen: DateTime.now(),
      );
      await savePairedDevice(updated);
    }
  }

  Future<void> clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceId);
    await prefs.remove(_keyDeviceName);
    await prefs.remove(_keyDeviceToken);
    await prefs.remove(_keyLastSeen);
    await prefs.remove(_keyDeviceIp);
    await prefs.remove(_keyDevicePort);
    await prefs.remove(_keyDevicesList);
  }

  Future<Map<String, dynamic>?> pairWithDevice(
    String ip,
    int port, {
    String? customToken,
    http.Client? client,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final url = Uri.parse('http://$ip:$port/pair');
      final body = customToken != null && customToken.isNotEmpty
          ? jsonEncode({'token': customToken})
          : '{}';
      final res = await httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {
      // Unreachable, timeout, or invalid response
    } finally {
      if (client == null) httpClient.close();
    }
    return null;
  }

  Future<bool> verifyDeviceConnectivity(
    String ip,
    int port,
    String token, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final url = Uri.parse('http://$ip:$port/status');
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await httpClient.get(
            url,
            headers: {'X-Buddy-Token': token},
          ).timeout(timeout);
          if (response.statusCode == 200) {
            return true;
          }
        } catch (_) {
          // Attempt failed or timed out
        }
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
