import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../volume/volume_repository.dart';
import 'pairing_repository.dart';

class LanDiscoveryService {
  final http.Client? _client;

  LanDiscoveryService({http.Client? client}) : _client = client;

  /// Discovers active local subnet prefixes from network interfaces (e.g. '192.168.1.').
  Future<List<String>> getLocalSubnetPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final lastDot = ip.lastIndexOf('.');
          if (lastDot != -1) {
            prefixes.add('${ip.substring(0, lastDot)}.');
          }
        }
      }
    } catch (e) {
      debugPrint('LanDiscoveryService: Could not inspect NetworkInterface: $e');
    }
    return prefixes.toList();
  }

  /// Probes a single IP on port [port] to check if it matches [expectedDeviceId].
  /// Returns the parsed JSON response body if matched, or null otherwise.
  Future<Map<String, dynamic>?> probeDevice({
    required String ip,
    int port = 8085,
    required String expectedDeviceId,
    String? token,
    http.Client? client,
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    final httpClient = client ?? _client ?? http.Client();
    try {
      final url = Uri.parse('http://$ip:$port/status');
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['X-Buddy-Token'] = token;
      }
      final response = await httpClient.get(url, headers: headers).timeout(timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final deviceId = body['deviceId'] as String? ?? body['id'] as String? ?? '';
        if (deviceId == expectedDeviceId) {
          return body;
        }
      }
    } catch (_) {
      // Offline, timeout, or port closed
    } finally {
      if (client == null && _client == null) {
        httpClient.close();
      }
    }
    return null;
  }

  /// Searches mDNS and the local Wi-Fi subnet for a device matching [deviceId].
  /// [candidateIps]: optional direct list of IPs to probe (ideal for tests or fixed IP pools).
  /// [subnetPrefix]: optional subnet prefix (e.g. '192.168.1.'). If omitted, discovers automatically.
  Future<String?> discoverDevice({
    required String deviceId,
    int port = 8085,
    String? token,
    List<String>? candidateIps,
    String? subnetPrefix,
    http.Client? client,
    Duration probeTimeout = const Duration(milliseconds: 600),
    int concurrency = 25,
  }) async {
    final httpClient = client ?? _client ?? http.Client();

    try {
      // 1. Try mDNS hostname resolution: FamilyLinkBuddy-<deviceId>.local
      try {
        final mDnsAddresses = await InternetAddress.lookup('FamilyLinkBuddy-$deviceId.local')
            .timeout(const Duration(milliseconds: 400));
        for (final addr in mDnsAddresses) {
          final res = await probeDevice(
            ip: addr.address,
            port: port,
            expectedDeviceId: deviceId,
            token: token,
            client: httpClient,
            timeout: probeTimeout,
          );
          if (res != null) {
            debugPrint('LanDiscoveryService: Located device via mDNS at ${addr.address}');
            return addr.address;
          }
        }
      } catch (_) {
        // mDNS not available or unresolvable
      }

      // 2. Prepare IP candidates to probe
      final List<String> ipsToProbe = [];
      if (candidateIps != null && candidateIps.isNotEmpty) {
        ipsToProbe.addAll(candidateIps);
      } else {
        final prefixes = <String>{};
        if (subnetPrefix != null && subnetPrefix.isNotEmpty) {
          prefixes.add(subnetPrefix.endsWith('.') ? subnetPrefix : '$subnetPrefix.');
        } else {
          final discovered = await getLocalSubnetPrefixes();
          prefixes.addAll(discovered);
        }

        for (final prefix in prefixes) {
          for (int i = 1; i <= 254; i++) {
            ipsToProbe.add('$prefix$i');
          }
        }
      }

      if (ipsToProbe.isEmpty) {
        return null;
      }

      // 3. Concurrently probe candidate IPs in batches
      for (int i = 0; i < ipsToProbe.length; i += concurrency) {
        final end = (i + concurrency).clamp(0, ipsToProbe.length);
        final batch = ipsToProbe.sublist(i, end);

        final futures = batch.map((ip) async {
          final res = await probeDevice(
            ip: ip,
            port: port,
            expectedDeviceId: deviceId,
            token: token,
            client: httpClient,
            timeout: probeTimeout,
          );
          return res != null ? ip : null;
        });

        final results = await Future.wait(futures);
        for (final foundIp in results) {
          if (foundIp != null) {
            debugPrint('LanDiscoveryService: Located device via subnet probe at $foundIp');
            return foundIp;
          }
        }
      }

      return null;
    } finally {
      if (client == null && _client == null) {
        httpClient.close();
      }
    }
  }

  /// Automatically re-discovers a paired device when unreachable.
  /// When found, updates [PairingRepository] and notifies [VolumeRepository].
  Future<String?> rediscoverDevice({
    required String deviceId,
    int port = 8085,
    String? token,
    required PairingRepository pairingRepository,
    VolumeRepository? volumeRepository,
    List<String>? candidateIps,
    String? subnetPrefix,
    http.Client? client,
  }) async {
    // Determine subnet prefix from existing cached IP if available
    String? prefix = subnetPrefix;
    if (prefix == null && candidateIps == null) {
      final current = await pairingRepository.loadPairedDevice();
      final cachedIp = current?.localIpAddress;
      if (cachedIp != null && cachedIp.contains('.')) {
        final lastDot = cachedIp.lastIndexOf('.');
        if (lastDot != -1) {
          prefix = '${cachedIp.substring(0, lastDot)}.';
        }
      }
    }

    final newIp = await discoverDevice(
      deviceId: deviceId,
      port: port,
      token: token,
      candidateIps: candidateIps,
      subnetPrefix: prefix,
      client: client,
    );

    if (newIp != null) {
      await pairingRepository.updateDeviceIp(newIp, port: port);
      if (volumeRepository != null) {
        volumeRepository.localIpAddress = newIp;
      }
    }

    return newIp;
  }
}
