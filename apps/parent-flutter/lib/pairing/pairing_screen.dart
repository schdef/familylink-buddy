import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../volume/volume_control_screen.dart';
import '../l10n/app_strings.dart';
import 'pairing_repository.dart';

class PairingScreen extends StatefulWidget {
  final http.Client? httpClient;
  final PairingRepository? repository;

  const PairingScreen({
    super.key,
    this.httpClient,
    this.repository,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final _deviceNameController = TextEditingController(text: 'Felix');
  final _deviceTokenController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  late final PairingRepository _repository;
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isProcessingScan = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PairingRepository();
  }

  // Handle scanned QR code payload
  Future<void> _handleScannedQr(String raw) async {
    final strings = context.strings;
    String ip = '10.0.2.2';
    int port = 8085;

    setState(() {
      _isScanning = false;
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = PairingQrPayload.tryParse(raw);
      if (payload == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = strings.invalidQrCode;
            _isProcessingScan = false;
          });
        }
        return;
      }

      ip = payload.ip.isNotEmpty
          ? payload.ip
          : (payload.token.contains('.') ? payload.token : '10.0.2.2');
      port = payload.port;
      final token = payload.token;

      final isReachable = await _repository.verifyDeviceConnectivity(
        ip,
        port,
        token,
        client: widget.httpClient,
      );

      if (!isReachable) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = strings.connectionFailedHint(ip, port);
            _isProcessingScan = false;
          });
        }
        return;
      }

      final childName = payload.deviceName.isNotEmpty
          ? payload.deviceName
          : (_deviceNameController.text.trim().isNotEmpty
              ? _deviceNameController.text.trim()
              : strings.defaultChildName);

      final device = PairedDevice(
        id: payload.deviceId.isNotEmpty ? payload.deviceId : payload.token,
        name: childName,
        token: payload.token,
        localIpAddress: ip,
        port: port,
        lastSeen: DateTime.now(),
      );

      await _repository.savePairedDevice(device);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isProcessingScan = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.successfullyPaired),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VolumeControlScreen(device: device),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = strings.connectionFailedHint(ip, port);
          _isProcessingScan = false;
        });
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _isProcessingScan = false;
        });
      }
    }
  }

  // 1. Direct Pairing using Device IP or Token
  Future<void> _handleDirectPairing() async {
    final strings = context.strings;
    final name = _deviceNameController.text.trim();
    final token = _deviceTokenController.text.trim();

    if (name.isEmpty || token.isEmpty) {
      setState(() {
        _error = strings.fillAllFields;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = PairingQrPayload.tryParse(token);
      final ip = payload?.ip.isNotEmpty == true
          ? payload!.ip
          : (token.contains('.') ? token : (token == 'emulator' ? '10.0.2.2' : null));
      final port = payload?.port ?? 8085;
      final finalToken = payload?.token.isNotEmpty == true ? payload!.token : token;
      final deviceId = payload?.deviceId.isNotEmpty == true ? payload!.deviceId : finalToken;

      final device = PairedDevice(
        id: deviceId,
        name: name,
        token: finalToken,
        lastSeen: DateTime.now(),
        localIpAddress: ip,
        port: port,
      );

      await _repository.savePairedDevice(device);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.successfullyPaired),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VolumeControlScreen(device: device),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = strings.pairingFailed(e);
      });
    }
  }

  // 2. Resolve Pairing using 6-Digit Code or IP
  Future<void> _handlePairingWithCode() async {
    final strings = context.strings;
    final code = _pairingCodeController.text.trim();
    final childName = _deviceNameController.text.trim().isNotEmpty
        ? _deviceNameController.text.trim()
        : strings.defaultChildName;

    if (code.isEmpty) {
      setState(() {
        _error = strings.enterCodeOrIp;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = PairingQrPayload.tryParse(code);
      final ip = payload?.ip.isNotEmpty == true
          ? payload!.ip
          : (code.contains('.') ? code : null);
      final port = payload?.port ?? 8085;
      var token = payload?.token.isNotEmpty == true ? payload!.token : code;
      var deviceId = payload?.deviceId.isNotEmpty == true ? payload!.deviceId : token;
      var resolvedName = (payload?.deviceName.isNotEmpty == true && payload!.deviceName != 'Kind')
          ? payload.deviceName
          : childName;

      if (ip != null) {
        final pairData = await _repository.pairWithDevice(
          ip,
          port,
          client: widget.httpClient,
        );

        if (pairData != null) {
          if (pairData['token'] is String && (pairData['token'] as String).isNotEmpty) {
            token = pairData['token'] as String;
          }
          if (pairData['deviceId'] is String && (pairData['deviceId'] as String).isNotEmpty) {
            deviceId = pairData['deviceId'] as String;
          }
          if (pairData['deviceName'] is String && (pairData['deviceName'] as String).isNotEmpty) {
            resolvedName = pairData['deviceName'] as String;
          }
        } else {
          final ok = await _repository.verifyDeviceConnectivity(
            ip,
            port,
            token,
            client: widget.httpClient,
          );
          if (!ok) {
            if (mounted) {
              setState(() {
                _error = strings.connectionFailedHint(ip, port);
              });
            }
            return;
          }
        }
      }

      final device = PairedDevice(
        id: deviceId,
        name: resolvedName,
        token: token,
        lastSeen: DateTime.now(),
        localIpAddress: ip,
        port: port,
      );

      await _repository.savePairedDevice(device);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.successfullyPaired),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VolumeControlScreen(device: device),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = strings.pairingFailed(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          title: Text(strings.scanQrCodeTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _scannerController.stop();
              setState(() {
                _isScanning = false;
                _isProcessingScan = false;
              });
            },
          ),
        ),
        body: MobileScanner(
          controller: _scannerController,
          onDetect: (capture) {
            if (_isLoading || _isProcessingScan || !_isScanning) return;
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final raw = barcode.rawValue;
              if (raw != null && raw.isNotEmpty) {
                _isProcessingScan = true;
                _scannerController.stop();
                _handleScannedQr(raw);
                break;
              }
            }
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(strings.pairDeviceTitle),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.pairChildLocally,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.pairChildLocallyDesc,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x26EF4444),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextField(
                      controller: _deviceNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: strings.deviceNameLabel,
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF6366F1)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // SECTION 1: Code / IP Entry
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.methodA,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pairingCodeController,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: strings.codeOrIpHint,
                              hintStyle: const TextStyle(color: Color(0xFF475569)),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Color(0xFF6366F1)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _handlePairingWithCode,
                            icon: const Icon(Icons.lan),
                            label: Text(strings.connect),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // SECTION 2: QR Code Scan
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isScanning = true;
                          _isProcessingScan = false;
                        });
                        _scannerController.start();
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(strings.methodB),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // DEV OVERRIDES
                    OutlinedButton.icon(
                      onPressed: () {
                        _deviceNameController.text = "Felix (Emulator)";
                        _deviceTokenController.text = "emulator";
                        _handleDirectPairing();
                      },
                      icon: const Icon(Icons.developer_board),
                      label: Text(strings.localEmulatorPairing),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _deviceNameController.dispose();
    _deviceTokenController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }
}
