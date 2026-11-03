import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/google_sign_in_service.dart';
import '../pairing/pairing_repository.dart';
import 'time_bank_repository.dart';
import 'time_bank_tasks_screen.dart';
import 'time_bank_activity_screen.dart';
import 'time_bank_settings_screen.dart';

class TimeBankScreen extends StatefulWidget {
  final ParentAccount? account;
  final PairedDevice device;

  const TimeBankScreen({
    super.key,
    this.account,
    required this.device,
  });

  @override
  State<TimeBankScreen> createState() => _TimeBankScreenState();
}

class _ScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _TimeBankScreenState extends State<TimeBankScreen> with SingleTickerProviderStateMixin {
  late TimeBankRepository _repository;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();

    _repository = Provider.of<TimeBankRepository>(context, listen: false);
    _repository.subscribeToDevice(widget.device.fcmToken);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _showAwardCoinsDialog() {
    final formKey = GlobalKey<FormState>();
    int selectedAmount = 15;
    String description = '';
    String emoji = '📚';

    final emojis = ['📚', '🧹', '🏃', '🐕', '🥦', '💡', '⏰', '⏳'];
    final quickAmounts = [5, 10, 15, 30, 60];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Coins vergeben ⏳', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Schnellauswahl:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: quickAmounts.map((amt) {
                          final isSelected = selectedAmount == amt;
                          return ChoiceChip(
                            label: Text('+$amt', style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8))),
                            selected: isSelected,
                            selectedColor: const Color(0xFF6366F1),
                            backgroundColor: const Color(0xFF0F172A),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  selectedAmount = amt;
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: description,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Grund (z.B. 30 Min gelesen)',
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
                          fillColor: const Color(0xFF0F172A),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Bitte einen Grund eingeben';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          description = val;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Symbol wählen:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: emojis.map((e) {
                          final isSelected = emoji == e;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                emoji = e;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF6366F1).withOpacity(0.2) : Colors.transparent,
                                border: Border.all(color: isSelected ? const Color(0xFF6366F1) : Colors.transparent, width: 2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(e, style: const TextStyle(fontSize: 24)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Abbrechen', style: TextStyle(color: Colors.white)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Vergeben ✓'),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(ctx).pop();
                      await _repository.awardCoins(widget.device.fcmToken, selectedAmount, description, emoji);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$selectedAmount Coins erfolgreich vergeben!')),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Zeitkonto'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TimeBankSettingsScreen(device: widget.device),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<TimeBankRepository>(
        builder: (context, repo, child) {
          final pendingClaims = repo.claims.where((c) => c.status == 'PENDING').toList();

          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScrollConfiguration(
              behavior: _ScrollBehavior(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status Badge (Enabled / Configured)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          repo.isEnabled ? 'Aktiviert' : 'Deaktiviert',
                          style: TextStyle(
                            color: repo.isEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          repo.isChildVisible ? 'Sichtbar für Kind' : 'Versteckt für Kind',
                          style: TextStyle(
                            color: repo.isChildVisible ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Balance Card
                    Center(
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E293B),
                          border: Border.all(color: const Color(0xFF6366F1), width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.2),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${repo.balance}',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Time Coins ⏳',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: repo.isEnabled ? _showAwardCoinsDialog : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Coins vergeben', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TimeBankTasksScreen(device: widget.device),
                              ),
                            ),
                            icon: const Icon(Icons.list),
                            label: const Text('Aufgaben & Bel.', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Pending Claims Alert Section
                    if (pendingClaims.isNotEmpty) ...[
                      const Text(
                        'Offene Auszahlungen',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...pendingClaims.map((claim) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Text(claim.emoji, style: const TextStyle(fontSize: 28)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      claim.title,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Kosten: ${claim.cost} Coins ⏳',
                                      style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Erledigt ✓'),
                                onPressed: () async {
                                  await repo.fulfillClaim(widget.device.fcmToken, claim.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Belohnung "${claim.title}" freigegeben.')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 24),
                    ],

                    // Transactions Log Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Aktivitäten von heute',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          child: const Text('Verlauf 📊', style: TextStyle(color: Color(0xFF6366F1))),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TimeBankActivityScreen(device: widget.device),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Today's Transactions List
                    if (repo.transactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'Heute noch keine Buchungen.',
                            style: TextStyle(color: Color(0xFF475569)),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: repo.transactions.length > 5 ? 5 : repo.transactions.length,
                        itemBuilder: (context, index) {
                          final tx = repo.transactions[index];
                          final isPositive = tx.amount >= 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Text(tx.emoji, style: const TextStyle(fontSize: 24)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tx.description,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${tx.timestamp.hour.toString().padLeft(2, '0')}:${tx.timestamp.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  isPositive ? '+${tx.amount}' : '${tx.amount}',
                                  style: TextStyle(
                                    color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
