import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'time_bank_repository.dart';
import '../l10n/app_strings.dart';
import '../pairing/pairing_repository.dart';

class TimeBankTasksScreen extends StatefulWidget {
  final PairedDevice device;

  const TimeBankTasksScreen({
    super.key,
    required this.device,
  });

  @override
  State<TimeBankTasksScreen> createState() => _TimeBankTasksScreenState();
}

class _TimeBankTasksScreenState extends State<TimeBankTasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TimeBankRepository _repository;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _repository = Provider.of<TimeBankRepository>(context, listen: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddTaskDialog() {
    final formKey = GlobalKey<FormState>();
    String title = '';
    String emoji = '📋';
    int reward = 10;
    bool hasDuration = false;
    int durationMinutes = 15;

    final emojis = ['📚', '🧹', '🏃', '🐕', '🥦', '💡', '⏰', '⏳'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(context.strings.createTaskTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: context.strings.taskTitleLabel,
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF334155)), borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF6366F1)), borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Bitte einen Titel eingeben';
                          return null;
                        },
                        onChanged: (val) => title = val,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: context.strings.rewardCoinsLabel,
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF334155)), borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF6366F1)), borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val) == null || int.parse(val) <= 0) {
                            return 'Bitte eine gültige Zahl eingeben';
                          }
                          return null;
                        },
                        onChanged: (val) => reward = int.tryParse(val) ?? 10,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mit Timer (Minuten):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                          Switch(
                            value: hasDuration,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) {
                              setDialogState(() {
                                hasDuration = val;
                              });
                            },
                          ),
                        ],
                      ),
                      if (hasDuration) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: durationMinutes.toString(),
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: context.strings.durationMinutesLabel,
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF334155)), borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF6366F1)), borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                          ),
                          validator: (val) {
                            if (val == null || int.tryParse(val) == null || int.parse(val) <= 0) {
                              return 'Bitte eine gültige Minutenzahl eingeben';
                            }
                            return null;
                          },
                          onChanged: (val) => durationMinutes = int.tryParse(val) ?? 15,
                        ),
                      ],
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
                  child: Text(context.strings.cancel, style: const TextStyle(color: Colors.white)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(context.strings.addButton),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(ctx).pop();
                      await _repository.createTask(widget.device.fcmToken, title, emoji, reward, hasDuration, durationMinutes);
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

  void _showAddRewardDialog() {
    final formKey = GlobalKey<FormState>();
    String title = '';
    String emoji = '🎁';
    int cost = 50;

    final emojis = ['🎁', '🎮', '📺', '🍿', '🎲', '🎡', '🍰', '🚲'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(context.strings.createRewardTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Titel (z.B. 1 Std. Minecraft)',
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF334155)), borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF6366F1)), borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Bitte einen Titel eingeben';
                          return null;
                        },
                        onChanged: (val) => title = val,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: context.strings.costCoinsLabel,
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF334155)), borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF6366F1)), borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val) == null || int.parse(val) <= 0) {
                            return 'Bitte eine gültige Zahl eingeben';
                          }
                          return null;
                        },
                        onChanged: (val) => cost = int.tryParse(val) ?? 50,
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
                  child: Text(context.strings.cancel, style: const TextStyle(color: Colors.white)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(context.strings.addButton),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(ctx).pop();
                      await _repository.createReward(widget.device.fcmToken, title, emoji, cost);
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
        title: Text(context.strings.tasksAndRewardsTitle),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6366F1),
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF94A3B8),
          tabs: const [
            Tab(text: 'Aufgaben 🌟', icon: Icon(Icons.star_outline)),
            Tab(text: 'Belohnungen 🎁', icon: Icon(Icons.card_giftcard)),
          ],
        ),
      ),
      body: Consumer<TimeBankRepository>(
        builder: (context, repo, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              // Tasks tab
              repo.tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.star_border, color: Color(0xFF475569), size: 64),
                          const SizedBox(height: 16),
                          const Text('Noch keine Aufgaben erstellt.', style: TextStyle(color: Color(0xFF94A3B8))),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Aufgabe hinzufügen'),
                            onPressed: _showAddTaskDialog,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: repo.tasks.length,
                      itemBuilder: (context, index) {
                        final task = repo.tasks[index];
                        return Card(
                          color: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ListTile(
                            leading: Text(task.emoji, style: const TextStyle(fontSize: 28)),
                            title: Text(task.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              task.hasDuration ? 'Timer: ${task.durationMinutes} Min | +${task.reward} Coins' : 'Direkt | +${task.reward} Coins',
                              style: const TextStyle(color: Color(0xFF94A3B8)),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                              onPressed: () async {
                                await repo.deleteTask(widget.device.fcmToken, task.id);
                              },
                            ),
                          ),
                        );
                      },
                    ),

              // Rewards tab
              repo.rewards.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.card_giftcard, color: Color(0xFF475569), size: 64),
                          const SizedBox(height: 16),
                          const Text('Noch keine Belohnungen erstellt.', style: TextStyle(color: Color(0xFF94A3B8))),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Belohnung hinzufügen'),
                            onPressed: _showAddRewardDialog,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: repo.rewards.length,
                      itemBuilder: (context, index) {
                        final reward = repo.rewards[index];
                        return Card(
                          color: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ListTile(
                            leading: Text(reward.emoji, style: const TextStyle(fontSize: 28)),
                            title: Text(reward.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text('Kosten: ${reward.cost} Coins ⏳', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                              onPressed: () async {
                                await repo.deleteReward(widget.device.fcmToken, reward.id);
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddTaskDialog();
          } else {
            _showAddRewardDialog();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
