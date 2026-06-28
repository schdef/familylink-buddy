import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'pairing_repository.dart';
import '../volume/volume_control_screen.dart';

class PairingScreen extends StatefulWidget {
  final GoogleSignInAccount? account;

  const PairingScreen({super.key, this.account});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _deviceNameController = TextEditingController(text: 'Kind-Gerät');
  final _deviceTokenController = TextEditingController();
  final _repository = PairingRepository();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkExistingPairing();
  }

  Future<void> _checkExistingPairing() async {
    setState(() { _isLoading = true; });
    final device = await _repository.loadPairedDevice();
    setState(() { _isLoading = false; });
    if (device != null && mounted) {
      _navigateToVolumeControl(device);
    }
  }

  void _navigateToVolumeControl(PairedDevice device) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => VolumeControlScreen(
          account: widget.account,
          device: device,
        ),
      ),
    );
  }

  Future<void> _handlePairing() async {
    final name = _deviceNameController.text.trim();
    final token = _deviceTokenController.text.trim();

    if (name.isEmpty || token.isEmpty) {
      setState(() {
        _error = 'Bitte füllen Sie alle Felder aus.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final device = PairedDevice(
      name: name,
      fcmToken: token,
      lastSeen: DateTime.now(),
    );

    await _repository.savePairedDevice(device);

    setState(() { _isLoading = false; });

    if (mounted) {
      _navigateToVolumeControl(device);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      'Neues Kinder-Gerät koppeln',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Kopieren Sie die Geräte-ID aus der FamilyLink Buddy App auf dem Gerät Ihres Kindes und fügen Sie sie hier ein.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                    const SizedBox(height: 32),
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
                    TextField(
                      controller: _deviceNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Geräte-Name (z.B. Emma)',
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _deviceTokenController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Geräte-ID (FCM Token)',
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
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _handlePairing,
                      icon: const Icon(Icons.link),
                      label: const Text('Verbinden & Koppeln'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    super.dispose();
  }
}
