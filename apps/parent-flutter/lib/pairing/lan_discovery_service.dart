import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../volume/volume_repository.dart';
import 'pairing_repository.dart';

class LanDiscoveryService {
  final http.Client? _client;
  final List<String>? defaultCandidateIps;

  LanDiscoveryService({http.Client? client, this.defaultCandidateIps}) : _client = client;

  /// Discovers active local subnet prefixes from network interfaces (e.g. '192.168.1.').
  Future<List<String>> getLocalSubnetPrefixes() async {
    final prefixes = <String>{};
    if (kIsWeb) {
      // In browser sandbox, raw network sockets are restricted; use common home router subnets
      return ['192.168.1.', '192.168.0.', '192.168.178.'];
    }
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
        final deviceName = body['deviceName'] as String? ?? '';
        final expected = expectedDeviceId.trim();

        if (expected.isEmpty ||
            deviceId.toLowerCase() == expected.toLowerCase() ||
            deviceName.toLowerCase() == expected.toLowerCase() ||
            deviceId.toLowerCase().contains(expected.toLowerCase()) ||
            deviceName.toLowerCase().contains(expected.toLowerCase())) {
          return body;
        }

        // If expected is a 6-digit code or pairing code:
        // Probe /pair to check if token prefix matches the 6-digit code
        if (expected.length == 6) {
          try {
            final pairUrl = Uri.parse('http://$ip:$port/pair');
            final pairRes = await httpClient.post(
              pairUrl,
              headers: {'Content-Type': 'application/json'},
              body: '{}',
            ).timeout(timeout);
            if (pairRes.statusCode == 200) {
              final pairData = jsonDecode(pairRes.body) as Map<String, dynamic>;
              final pToken = pairData['token'] as String? ?? '';
              final pCode = pToken.length >= 6
                  ? pToken.substring(0, 6).toUpperCase()
                  : pToken.toUpperCase();
              if (pCode == expected.toUpperCase() ||
                  pToken.toUpperCase().contains(expected.toUpperCase())) {
                return pairData;
              }
            }
          } catch (_) {
            // Ignore pair probe failure
          }
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

    final List<String>? explicitCandidates = candidateIps ?? defaultCandidateIps;
    final List<String> ipsToProbe = [];

    try {
      if (explicitCandidates != null && explicitCandidates.isNotEmpty) {
        ipsToProbe.addAll(explicitCandidates);
      } else {
        // 1. Try mDNS hostname resolution: FamilyLinkBuddy-<deviceId>.local (native only)
        if (!kIsWeb) {
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
        }

        // 2. Prepare IP candidates to probe
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

        if (prefixes.isEmpty) {
          ipsToProbe.addAll(['10.0.2.2', '127.0.0.1', 'localhost']);
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
