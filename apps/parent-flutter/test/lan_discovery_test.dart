import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parent_app/pairing/lan_discovery_service.dart';
import 'package:parent_app/pairing/pairing_repository.dart';
import 'package:parent_app/volume/volume_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('LanDiscoveryService Unit Tests', () {
    test('probeDevice returns payload when deviceId matches', () async {
      final mockClient = MockHttpClient((req) async {
        expect(req.url.path, '/status');
        return http.Response(
          jsonEncode({
            'status': 'online',
            'deviceId': 'target-tab-123',
            'deviceName': 'Felix Galaxy Tab',
          }),
          200,
        );
      });

      final service = LanDiscoveryService(client: mockClient);
      final result = await service.probeDevice(
        ip: '192.168.1.44',
        port: 8085,
        expectedDeviceId: 'target-tab-123',
      );

      expect(result, isNotNull);
      expect(result!['deviceId'], 'target-tab-123');
      expect(result['deviceName'], 'Felix Galaxy Tab');
    });

    test('probeDevice returns null when deviceId does not match', () async {
      final mockClient = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'status': 'online',
            'deviceId': 'other-device-999',
          }),
          200,
        );
      });

      final service = LanDiscoveryService(client: mockClient);
      final result = await service.probeDevice(
        ip: '192.168.1.44',
        port: 8085,
        expectedDeviceId: 'target-tab-123',
      );

      expect(result, isNull);
    });

    test('probeDevice returns null on server error or connection failure', () async {
      final mockClient = MockHttpClient((req) async {
        return http.Response('Error', 500);
      });

      final service = LanDiscoveryService(client: mockClient);
      final result = await service.probeDevice(
        ip: '192.168.1.44',
        port: 8085,
        expectedDeviceId: 'target-tab-123',
      );

      expect(result, isNull);
    });

    test('discoverDevice finds matching device across candidate IPs', () async {
      final mockClient = MockHttpClient((req) async {
        if (req.url.host == '192.168.1.88') {
          return http.Response(
            jsonEncode({
              'status': 'online',
              'deviceId': 'felix-tab-id',
              'deviceName': 'Felix Pixel',
            }),
            200,
          );
        }
        return http.Response('Connection refused', 404);
      });

      final service = LanDiscoveryService(client: mockClient);
      final foundIp = await service.discoverDevice(
        deviceId: 'felix-tab-id',
        port: 8085,
        candidateIps: ['192.168.1.10', '192.168.1.50', '192.168.1.88', '192.168.1.100'],
      );

      expect(foundIp, '192.168.1.88');
    });

    test('discoverDevice returns null if no IP matches deviceId', () async {
      final mockClient = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({'deviceId': 'someone-else'}),
          200,
        );
      });

      final service = LanDiscoveryService(client: mockClient);
      final foundIp = await service.discoverDevice(
        deviceId: 'felix-tab-id',
        candidateIps: ['192.168.1.10', '192.168.1.20'],
      );

      expect(foundIp, isNull);
    });

    test('rediscoverDevice updates PairingRepository and notifies VolumeRepository', () async {
      SharedPreferences.setMockInitialValues({});
      final pairingRepo = PairingRepository();

      // Initial paired state with old IP
      await pairingRepo.savePairedDevice(
        PairedDevice(
          id: 'felix-target-device',
          name: 'Felix Phone',
          token: 'token-abc',
          localIpAddress: '192.168.1.20', // Outdated IP (e.g. DHCP reassigned)
          lastSeen: DateTime.now(),
        ),
      );

      final volumeRepo = VolumeRepository();
      volumeRepo.localIpAddress = '192.168.1.20';

      final mockClient = MockHttpClient((req) async {
        // Old IP is down / unreachable
        if (req.url.host == '192.168.1.20') {
          throw Exception('Host unreachable');
        }
        // New DHCP IP responds
        if (req.url.host == '192.168.1.75') {
          return http.Response(
            jsonEncode({
              'status': 'online',
              'deviceId': 'felix-target-device',
              'deviceName': 'Felix Phone',
            }),
            200,
          );
        }
        throw Exception('Offline');
      });

      final service = LanDiscoveryService(client: mockClient);

      // Re-discover device
      final newIp = await service.rediscoverDevice(
        deviceId: 'felix-target-device',
        token: 'token-abc',
        pairingRepository: pairingRepo,
        volumeRepository: volumeRepo,
        candidateIps: ['192.168.1.20', '192.168.1.50', '192.168.1.75'],
      );

      expect(newIp, '192.168.1.75');

      // Verify PairingRepository was updated
      final updatedDevice = await pairingRepo.loadPairedDevice();
      expect(updatedDevice, isNotNull);
      expect(updatedDevice!.localIpAddress, '192.168.1.75');
      expect(updatedDevice.id, 'felix-target-device');

      // Verify VolumeRepository localIpAddress was updated
      expect(volumeRepo.localIpAddress, '192.168.1.75');
    });
  });
}
