import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pairing_repository.dart';
import '../auth/google_family_link_service.dart';
import '../auth/google_sign_in_service.dart';

class PairingScreen extends StatefulWidget {
  final ParentAccount? account;

  const PairingScreen({super.key, this.account});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _deviceNameController = TextEditingController(text: 'Felix');
  final _deviceTokenController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  final _repository = PairingRepository();
  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;

  List<FamilyMember> _familyChildren = [];
  FamilyMember? _selectedChild;
  bool _isLoadingFamily = false;

  @override
  void initState() {
    super.initState();
    _fetchFamilyChildren();
  }

  Future<void> _fetchFamilyChildren() async {
    setState(() { _isLoadingFamily = true; });
    try {
      final email = widget.account?.email ?? 'stefanheintz@gmail.com';
      final kids = await GoogleFamilyLinkService.fetchChildren(email);
      setState(() {
        _familyChildren = kids;
        if (kids.isNotEmpty) {
          _selectedChild = kids.first;
        }
        _isLoadingFamily = false;
      });
    } catch (e) {
      setState(() { _isLoadingFamily = false; });
    }
  }

  // 1. Direct Pairing using FCM Token
  Future<void> _handleDirectPairing() async {
    final name = _selectedChild?.name ?? _deviceNameController.text.trim();
    final token = _deviceTokenController.text.trim();

    if (name.isEmpty || token.isEmpty) {
      setState(() { _error = 'Bitte füllen Sie alle Felder aus.'; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final parentId = widget.account?.id ?? 'mock-parent-uid';
      await FirebaseFirestore.instance.collection('pairings').doc(token).set({
        'parentId': parentId,
        'deviceName': name,
        'lastSeen': FieldValue.serverTimestamp()
      });

      final device = PairedDevice(
        name: name,
        fcmToken: token,
        lastSeen: DateTime.now(),
      );

      await _repository.savePairedDevice(device);
      setState(() { _isLoading = false; });

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Direkte Kopplung fehlgeschlagen: $e';
      });
    }
  }

  // 2. Resolve Pairing using 6-Digit Code via Direct Firestore
  Future<void> _handlePairingWithCode() async {
    final code = _pairingCodeController.text.trim();
    final childName = _selectedChild?.name ?? 'Kind';

    if (code.isEmpty) {
      setState(() { _error = 'Bitte geben Sie den 6-stelligen Code ein.'; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final codeDoc = await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .get();

      if (!codeDoc.exists) {
        throw 'Der eingegebene Code ist ungültig oder abgelaufen.';
      }

      final codeData = codeDoc.data();
      if (codeData == null) {
        throw 'Dokumentdaten sind leer.';
      }

      final childToken = codeData['fcmToken'] as String;
      final parentId = widget.account?.id ?? 'mock-parent-uid';
      final volumeReport = codeData['volumeReport'] as Map<dynamic, dynamic>?;

      // 1. Create pairings document directly with the child's Family Link API name
      await FirebaseFirestore.instance
          .collection('pairings')
          .doc(childToken)
          .set({
            'parentId': parentId,
            'deviceName': childName,
            'lastSeen': FieldValue.serverTimestamp(),
            'volumeReport': volumeReport
          });

      // 2. Delete temporary pairing code
      await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .delete();

      final device = PairedDevice(
        name: childName,
        fcmToken: childToken,
        lastSeen: DateTime.now(),
      );

      await _repository.savePairedDevice(device);
      setState(() { _isLoading = false; });

      if (mounted) {
        Navigator.of(context).pop(); // Go back to DeviceListScreen dashboard
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Kopplung fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('QR Code scannen'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _isScanning = false),
          ),
        ),
        body: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final raw = barcode.rawValue;
              if (raw != null && raw.isNotEmpty) {
                setState(() {
                  _deviceTokenController.text = raw;
                  _isScanning = false;
                });
                _handleDirectPairing();
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
        title: const Text('Gerät koppeln'),
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
                    const Text(
                      'Kinder-Gerät koppeln',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Koppeln Sie das Gerät Ihres Kindes per 6-stelligem Code oder QR-Code.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Family Link Supervised Kid Dropdown Selector
                    if (_isLoadingFamily) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else if (_familyChildren.isNotEmpty) ...[
                      DropdownButtonFormField<FamilyMember>(
                        value: _selectedChild,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Kind aus Family Link auswählen',
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
                        items: _familyChildren.map((child) => DropdownMenuItem(
                          value: child,
                          child: Text('${child.name} (${child.email})'),
                        )).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedChild = val;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      // Fallback input if Family Link API fails/empty
                      TextField(
                        controller: _deviceNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Geräte-Name (z.B. Felix)',
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
                    ],

                    // SECTION 1: 6-Digit Code Pairing
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
                          const Text(
                            'Methode A: 6-stelliger Code',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pairingCodeController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: '123 456',
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
                            icon: const Icon(Icons.pin),
                            label: const Text('Per PIN-Code verbinden'),
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
                      onPressed: () => setState(() => _isScanning = true),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Methode B: QR-Code scannen'),
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
                      label: const Text('Lokale Emulator-Kopplung (Auto-Pair)'),
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
    _deviceNameController.dispose();
    _deviceTokenController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }
}
