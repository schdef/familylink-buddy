import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pairing_screen.dart';
import 'pairing_repository.dart';
import '../volume/volume_control_screen.dart';
import '../volume/volume_repository.dart';
import '../auth/google_sign_in_service.dart';
import '../auth/sign_in_screen.dart';

class DeviceListScreen extends StatefulWidget {
  final GoogleSignInAccount? account;

  const DeviceListScreen({super.key, this.account});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  Future<void> _handleSignOut() async {
    await GoogleSignInService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentId = widget.account?.id ?? 'mock-parent-uid';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Meine Kinder / Geräte'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Abmelden?', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Möchten Sie sich abmelden?',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Abbrechen', style: TextStyle(color: Colors.white)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    TextButton(
                      child: const Text('Abmelden', style: TextStyle(color: Color(0xFFEF4444))),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _handleSignOut();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pairings')
            .where('parentId', isEqualTo: parentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Fehler beim Laden der Geräte: ${snapshot.error}',
                style: const TextStyle(color: Color(0xFFEF4444)),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_outline, color: Color(0xFF475569), size: 80),
                    const SizedBox(height: 24),
                    const Text(
                      'Noch keine Kinder gekoppelt',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Koppeln Sie das Gerät Ihres Kindes, um dessen Lautstärke aus der Ferne zu steuern.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PairingScreen(account: widget.account),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Gerät koppeln'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final childToken = doc.id;
              final name = data['deviceName'] as String? ?? 'Kind';
              final lastSeenStamp = data['lastSeen'] as Timestamp?;
              final lastSeen = lastSeenStamp?.toDate() ?? DateTime.now();

              // Calculate active status (online if seen in the last 60 seconds)
              final isOnline = DateTime.now().difference(lastSeen).inSeconds < 60;

              // Parse volume levels summary
              final report = data['volumeReport'] as Map<dynamic, dynamic>?;
              final mediaVol = (report?['mediaVolume'] as num?)?.toInt() ?? -1;
              final maxMedia = (report?['maxMediaVolume'] as num?)?.toInt() ?? 15;

              return Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: const Color(0xFF334155).withOpacity(0.5)),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    // Navigate to VolumeControlScreen for this child device
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VolumeControlScreen(
                          account: widget.account,
                          device: PairedDevice(
                            name: name,
                            fcmToken: childToken,
                            lastSeen: lastSeen,
                          ),
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        // Supervised Child Avatar
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.child_care,
                            color: Color(0xFF6366F1),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Kid Information
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? 'Online' : 'Standby / Offline',
                                    style: TextStyle(
                                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Volume Summary Indicator
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (mediaVol >= 0) ...[
                              Row(
                                children: [
                                  const Icon(Icons.volume_up, color: Color(0xFF94A3B8), size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$mediaVol/$maxMedia',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const Text(
                                'Kein Bericht',
                                style: TextStyle(color: Color(0xFF475569), fontSize: 13),
                              ),
                            ],
                            const SizedBox(height: 4),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Color(0xFF475569),
                              size: 14,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pairings')
            .where('parentId', isEqualTo: parentId)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const SizedBox.shrink(); // Don't duplicate the button

          return FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PairingScreen(account: widget.account),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Kind hinzufügen'),
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
          );
        },
      ),
    );
  }
}
