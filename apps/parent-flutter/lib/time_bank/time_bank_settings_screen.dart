import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'time_bank_repository.dart';
import '../l10n/app_strings.dart';
import '../pairing/pairing_repository.dart';

class TimeBankSettingsScreen extends StatefulWidget {
  final PairedDevice device;

  const TimeBankSettingsScreen({
    super.key,
    required this.device,
  });

  @override
  State<TimeBankSettingsScreen> createState() => _TimeBankSettingsScreenState();
}

class _TimeBankSettingsScreenState extends State<TimeBankSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(context.strings.timeBankSettingsTitle),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Consumer<TimeBankRepository>(
        builder: (context, repo, child) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Main description card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF6366F1)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Richten Sie hier das Belohnungssystem ein. Das Kind verdient Coins für Aufgaben und kann diese gegen Belohnungen eintauschen.',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Switch 1: timeBankEnabled
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Zeitkonto aktivieren',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Switch(
                            value: repo.isEnabled,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) async {
                              await repo.setTimeBankEnabled(widget.device.fcmToken, val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Schaltet das Münzsystem und das Eintragen von Transaktionen/Aufgaben frei.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Switch 2: timeBankChildVisible
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Für Kind sichtbar',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Switch(
                            value: repo.isChildVisible,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) async {
                              await repo.setChildVisible(widget.device.fcmToken, val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Wenn diese Option aktiviert ist, kann das Kind sein Guthaben, Aufgaben und den Shop in der eigenen App einsehen. Wenn sie deaktiviert ist, bleibt das Feature für das Kind komplett unsichtbar.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
