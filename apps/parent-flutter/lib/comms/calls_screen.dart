import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import 'comms_models.dart';
import 'comms_repository.dart';
import '../l10n/app_strings.dart';

class CallsScreen extends StatefulWidget {
  final PairedDevice device;
  final String? localIpAddress;

  const CallsScreen({
    super.key,
    required this.device,
    this.localIpAddress,
  });

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final TextEditingController _searchController = TextEditingController();
  CallType? _selectedTypeFilter; // null = All
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final repo = Provider.of<CommsRepository>(context, listen: false);
        repo.loadCache(widget.device.id);
        _autoSyncIfPossible();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _effectiveIp {
    if (widget.localIpAddress != null && widget.localIpAddress!.isNotEmpty) {
      return widget.localIpAddress!;
    }
    if (widget.device.localIpAddress != null &&
        widget.device.localIpAddress!.isNotEmpty) {
      return widget.device.localIpAddress!;
    }
    return '';
  }

  Future<void> _autoSyncIfPossible() async {
    final ip = _effectiveIp;
    if (ip.isNotEmpty) {
      final repo = Provider.of<CommsRepository>(context, listen: false);
      await repo.syncLogs(ip, widget.device.token, widget.device.id);
    }
  }

  Future<void> _handleManualSync() async {
    final ip = _effectiveIp;
    final strings = context.strings;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.syncFailed),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final repo = Provider.of<CommsRepository>(context, listen: false);
    final success = await repo.syncLogs(ip, widget.device.token, widget.device.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.syncSuccess),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(repo.errorMessage ?? strings.syncFailed),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatTimestamp(DateTime dt, AppStrings strings) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    if (isToday) {
      return '${strings.today} $timeStr';
    } else if (isYesterday) {
      return '${strings.yesterday} $timeStr';
    } else {
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} $timeStr';
    }
  }

  Color _getCallColor(CallType type) {
    switch (type) {
      case CallType.incoming:
        return const Color(0xFF10B981); // Emerald Green
      case CallType.outgoing:
        return const Color(0xFF3B82F6); // Blue
      case CallType.missed:
      case CallType.rejected:
        return const Color(0xFFEF4444); // Red
    }
  }

  IconData _getCallIcon(CallType type) {
    switch (type) {
      case CallType.incoming:
        return Icons.call_received_rounded;
      case CallType.outgoing:
        return Icons.call_made_rounded;
      case CallType.missed:
        return Icons.call_missed_rounded;
      case CallType.rejected:
        return Icons.call_missed_outgoing_rounded;
    }
  }

  String _getCallTypeLabel(CallType type, AppStrings strings) {
    switch (type) {
      case CallType.incoming:
        return strings.incomingLabel;
      case CallType.outgoing:
        return strings.outgoingLabel;
      case CallType.missed:
        return strings.missedLabel;
      case CallType.rejected:
        return strings.rejectedLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.callHistoryTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.device.name,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          Consumer<CommsRepository>(
            builder: (context, repo, _) {
              if (repo.isLoading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                key: const ValueKey('calls_sync_button'),
                icon: const Icon(Icons.sync_rounded, color: Color(0xFFF59E0B)),
                tooltip: strings.syncNow,
                onPressed: _handleManualSync,
              );
            },
          ),
        ],
      ),
      body: Consumer<CommsRepository>(
        builder: (context, repo, _) {
          // Filter calls
          final filteredCalls = repo.calls.where((call) {
            // Type filter
            if (_selectedTypeFilter != null) {
              if (_selectedTypeFilter == CallType.missed) {
                if (call.callType != CallType.missed && call.callType != CallType.rejected) {
                  return false;
                }
              } else if (call.callType != _selectedTypeFilter) {
                return false;
              }
            }

            // Search query filter
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final matchesPhone = call.phoneNumber.toLowerCase().contains(q);
              final matchesName = call.contactName?.toLowerCase().contains(q) ?? false;
              if (!matchesPhone && !matchesName) return false;
            }

            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: _handleManualSync,
            color: const Color(0xFFF59E0B),
            backgroundColor: const Color(0xFF1E293B),
            child: Column(
              children: [
                // Sync status banner
                _buildSyncBanner(repo, strings),

                // Search Bar
                _buildSearchBar(strings),

                // Filter Chips
                _buildFilterChips(strings),

                const SizedBox(height: 8),

                // Calls List or Empty State
                Expanded(
                  child: filteredCalls.isEmpty
                      ? _buildEmptyState(strings, repo.calls.isEmpty)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredCalls.length,
                          itemBuilder: (context, index) {
                            final call = filteredCalls[index];
                            return _buildCallCard(call, strings);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSyncBanner(CommsRepository repo, AppStrings strings) {
    final syncText = repo.lastSyncedAt != null
        ? strings.lastSyncedLabel(_formatTimestamp(repo.lastSyncedAt!, strings))
        : strings.offlineNotice;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
      child: Row(
        children: [
          Icon(
            repo.lastSyncedAt != null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            size: 14,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Text(
            syncText,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: TextField(
          key: const ValueKey('calls_search_input'),
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: strings.searchCallsPlaceholder,
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val.trim());
          },
        ),
      ),
    );
  }

  Widget _buildFilterChips(AppStrings strings) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildFilterChip(
            key: const ValueKey('filter_chip_all'),
            label: strings.allCalls,
            isSelected: _selectedTypeFilter == null,
            onSelected: () => setState(() => _selectedTypeFilter = null),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('filter_chip_incoming'),
            label: strings.incomingCalls,
            isSelected: _selectedTypeFilter == CallType.incoming,
            onSelected: () => setState(() => _selectedTypeFilter = CallType.incoming),
            icon: Icons.call_received_rounded,
            activeColor: const Color(0xFF10B981),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('filter_chip_outgoing'),
            label: strings.outgoingCalls,
            isSelected: _selectedTypeFilter == CallType.outgoing,
            onSelected: () => setState(() => _selectedTypeFilter = CallType.outgoing),
            icon: Icons.call_made_rounded,
            activeColor: const Color(0xFF3B82F6),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('filter_chip_missed'),
            label: strings.missedCalls,
            isSelected: _selectedTypeFilter == CallType.missed,
            onSelected: () => setState(() => _selectedTypeFilter = CallType.missed),
            icon: Icons.call_missed_rounded,
            activeColor: const Color(0xFFEF4444),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    Key? key,
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    IconData? icon,
    Color? activeColor,
  }) {
    final color = activeColor ?? const Color(0xFFF59E0B);
    return InkWell(
      key: key,
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? color : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : const Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallCard(CallRecord call, AppStrings strings) {
    final color = _getCallColor(call.callType);
    final icon = _getCallIcon(call.callType);
    final hasContactName = call.contactName != null && call.contactName!.trim().isNotEmpty;
    final primaryTitle = hasContactName ? call.contactName!.trim() : call.phoneNumber;
    final secondaryPhone = hasContactName ? call.phoneNumber : null;

    final durationText = (call.callType == CallType.missed || call.callType == CallType.rejected)
        ? _getCallTypeLabel(call.callType, strings)
        : strings.callDurationFormat(call.durationSeconds);

    return Container(
      key: ValueKey('call_record_item_${call.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          // Icon avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (secondaryPhone != null) ...[
                      Text(
                        secondaryPhone,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                    Text(
                      durationText,
                      style: TextStyle(
                        color: (call.callType == CallType.missed || call.callType == CallType.rejected)
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Timestamp & Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTimestamp(call.dateTime, strings),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getCallTypeLabel(call.callType, strings),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppStrings strings, bool isCompletelyEmpty) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Icon(
              Icons.phone_disabled_rounded,
              size: 40,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          strings.noCallsFound,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isCompletelyEmpty
              ? strings.offlineNotice
              : strings.searchCallsPlaceholder,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
          ),
        ),
        if (isCompletelyEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: Text(strings.syncNow),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _handleManualSync,
            ),
          ),
        ],
      ],
    );
  }
}
