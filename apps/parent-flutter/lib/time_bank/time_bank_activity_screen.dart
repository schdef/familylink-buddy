import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'time_bank_repository.dart';
import '../l10n/app_strings.dart';
import '../pairing/pairing_repository.dart';

class TimeBankActivityScreen extends StatefulWidget {
  final PairedDevice device;

  const TimeBankActivityScreen({
    super.key,
    required this.device,
  });

  @override
  State<TimeBankActivityScreen> createState() => _TimeBankActivityScreenState();
}

class _TimeBankActivityScreenState extends State<TimeBankActivityScreen> {
  int _selectedFilter = 0; // 0 = Tag, 1 = Woche, 2 = Monat

  List<TransactionModel> _filterTransactions(List<TransactionModel> txs) {
    final now = DateTime.now();
    if (_selectedFilter == 0) {
      // Last 24 hours / today
      return txs.where((t) {
        final diff = now.difference(t.timestamp).inDays;
        return diff == 0 && t.timestamp.day == now.day;
      }).toList();
    } else if (_selectedFilter == 1) {
      // Last 7 days
      return txs.where((t) {
        final diff = now.difference(t.timestamp).inDays;
        return diff <= 7;
      }).toList();
    } else {
      // Current month
      return txs.where((t) {
        return t.timestamp.month == now.month && t.timestamp.year == now.year;
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(context.strings.activityHistoryTitle),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Consumer<TimeBankRepository>(
        builder: (context, repo, child) {
          final filteredTxs = _filterTransactions(repo.transactions);

          int earned = 0;
          int spent = 0;

          for (var tx in filteredTxs) {
            if (tx.amount >= 0) {
              earned += tx.amount;
            } else {
              spent += tx.amount.abs();
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Segmented Filter Bar
              Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedFilter = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedFilter == 0 ? const Color(0xFF6366F1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Heute',
                            style: TextStyle(
                              color: _selectedFilter == 0 ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedFilter = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedFilter == 1 ? const Color(0xFF6366F1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Woche',
                            style: TextStyle(
                              color: _selectedFilter == 1 ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedFilter = 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedFilter == 2 ? const Color(0xFF6366F1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Monat',
                            style: TextStyle(
                              color: _selectedFilter == 2 ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Summary Card
              Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Verdient', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                            '+$earned ⏳',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 40, color: const Color(0xFF334155)),
                      Column(
                        children: [
                          const Text('Ausgegeben', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                            '-$spent ⏳',
                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Transactions list
              Expanded(
                child: filteredTxs.isEmpty
                    ? const Center(
                        child: Text(
                          'Keine Aktivitäten in diesem Zeitraum.',
                          style: TextStyle(color: Color(0xFF475569)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: filteredTxs.length,
                        itemBuilder: (context, index) {
                          final tx = filteredTxs[index];
                          final isPositive = tx.amount >= 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF334155).withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Text(tx.emoji, style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tx.description,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${tx.timestamp.day}.${tx.timestamp.month}.${tx.timestamp.year} — ${tx.timestamp.hour.toString().padLeft(2, '0')}:${tx.timestamp.minute.toString().padLeft(2, '0')}',
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
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
