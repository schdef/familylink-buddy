import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import 'comms_models.dart';
import 'comms_repository.dart';
import '../l10n/app_strings.dart';

enum ChatAppFilter {
  all,
  whatsapp,
  sms,
  telegram,
  signal;

  bool matches(ChatMessageRecord msg) {
    if (this == ChatAppFilter.all) return true;
    final pkg = msg.appPackage.toLowerCase();
    final name = msg.appName.toLowerCase();

    switch (this) {
      case ChatAppFilter.whatsapp:
        return pkg.contains('whatsapp') || name.contains('whatsapp');
      case ChatAppFilter.sms:
        return pkg.contains('messaging') ||
            pkg.contains('sms') ||
            pkg.contains('mms') ||
            name.contains('sms') ||
            name.contains('message');
      case ChatAppFilter.telegram:
        return pkg.contains('telegram') || name.contains('telegram');
      case ChatAppFilter.signal:
        return pkg.contains('securesms') ||
            pkg.contains('signal') ||
            name.contains('signal');
      case ChatAppFilter.all:
        return true;
    }
  }
}

class ChatAppHelper {
  static Color getAppColor(String appPackage, String appName) {
    final pkg = appPackage.toLowerCase();
    final name = appName.toLowerCase();

    if (pkg.contains('whatsapp') || name.contains('whatsapp')) {
      return const Color(0xFF25D366); // WhatsApp Green
    }
    if (pkg.contains('telegram') || name.contains('telegram')) {
      return const Color(0xFF0088CC); // Telegram Blue
    }
    if (pkg.contains('securesms') || pkg.contains('signal') || name.contains('signal')) {
      return const Color(0xFF3A76F0); // Signal Indigo
    }
    return const Color(0xFF3B82F6); // SMS / Messages Blue
  }

  static IconData getAppIcon(String appPackage, String appName) {
    final pkg = appPackage.toLowerCase();
    final name = appName.toLowerCase();

    if (pkg.contains('whatsapp') || name.contains('whatsapp')) {
      return Icons.chat_rounded;
    }
    if (pkg.contains('telegram') || name.contains('telegram')) {
      return Icons.send_rounded;
    }
    if (pkg.contains('securesms') || pkg.contains('signal') || name.contains('signal')) {
      return Icons.lock_rounded;
    }
    return Icons.sms_rounded;
  }

  static String getAppDisplayName(
    String appPackage,
    String appName,
    AppStrings strings,
  ) {
    final pkg = appPackage.toLowerCase();
    final name = appName.toLowerCase();

    if (pkg.contains('whatsapp') || name.contains('whatsapp')) {
      return strings.appWhatsApp;
    }
    if (pkg.contains('telegram') || name.contains('telegram')) {
      return strings.appTelegram;
    }
    if (pkg.contains('securesms') || pkg.contains('signal') || name.contains('signal')) {
      return strings.appSignal;
    }
    if (pkg.contains('messaging') ||
        pkg.contains('sms') ||
        pkg.contains('mms') ||
        name.contains('sms') ||
        name.contains('message')) {
      return strings.appSms;
    }
    return appName.isNotEmpty ? appName : strings.appSms;
  }
}

class ChatThread {
  final String conversationKey;
  final String senderOrChat;
  final String appPackage;
  final String appName;
  final List<ChatMessageRecord> messages; // sorted ascending by time

  const ChatThread({
    required this.conversationKey,
    required this.senderOrChat,
    required this.appPackage,
    required this.appName,
    required this.messages,
  });

  ChatMessageRecord get latestMessage => messages.last;
}

class ChatsScreen extends StatefulWidget {
  final PairedDevice device;
  final String? localIpAddress;

  const ChatsScreen({
    super.key,
    required this.device,
    this.localIpAddress,
  });

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  ChatAppFilter _selectedFilter = ChatAppFilter.all;
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

  List<ChatThread> _buildThreads(List<ChatMessageRecord> rawChats) {
    // 1. Filter by App and Search Query
    final filtered = rawChats.where((msg) {
      if (!_selectedFilter.matches(msg)) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesSender = msg.senderOrChat.toLowerCase().contains(q);
        final matchesText = msg.text.toLowerCase().contains(q);
        if (!matchesSender && !matchesText) return false;
      }
      return true;
    }).toList();

    // 2. Group by (appPackage + senderOrChat)
    final Map<String, List<ChatMessageRecord>> grouped = {};
    for (final msg in filtered) {
      final key = '${msg.appPackage}:::${msg.senderOrChat}';
      grouped.putIfAbsent(key, () => []).add(msg);
    }

    // 3. Convert to ChatThread list
    final List<ChatThread> threads = [];
    grouped.forEach((key, list) {
      // Sort messages chronologically ascending
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final first = list.first;
      threads.add(ChatThread(
        conversationKey: key,
        senderOrChat: first.senderOrChat,
        appPackage: first.appPackage,
        appName: first.appName,
        messages: list,
      ));
    });

    // 4. Sort threads descending by latest message timestamp
    threads.sort((a, b) => b.latestMessage.timestamp.compareTo(a.latestMessage.timestamp));
    return threads;
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
              strings.chatMessagesTitle,
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
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF14B8A6)),
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                key: const ValueKey('chats_sync_button'),
                icon: const Icon(Icons.sync_rounded, color: Color(0xFF14B8A6)),
                tooltip: strings.syncNow,
                onPressed: _handleManualSync,
              );
            },
          ),
        ],
      ),
      body: Consumer<CommsRepository>(
        builder: (context, repo, _) {
          final threads = _buildThreads(repo.chats);

          return RefreshIndicator(
            onRefresh: _handleManualSync,
            color: const Color(0xFF14B8A6),
            backgroundColor: const Color(0xFF1E293B),
            child: Column(
              children: [
                // Sync status banner
                _buildSyncBanner(repo, strings),

                // Search Bar
                _buildSearchBar(strings),

                // App Filter Chips
                _buildFilterChips(strings),

                const SizedBox(height: 8),

                // Conversation Threads List or Empty State
                Expanded(
                  child: threads.isEmpty
                      ? _buildEmptyState(strings, repo.chats.isEmpty)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: threads.length,
                          itemBuilder: (context, index) {
                            final thread = threads[index];
                            return _buildThreadCard(thread, strings);
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
          key: const ValueKey('chats_search_input'),
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: strings.searchChatsPlaceholder,
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
            key: const ValueKey('app_filter_all'),
            label: strings.allApps,
            isSelected: _selectedFilter == ChatAppFilter.all,
            onSelected: () => setState(() => _selectedFilter = ChatAppFilter.all),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('app_filter_whatsapp'),
            label: strings.appWhatsApp,
            isSelected: _selectedFilter == ChatAppFilter.whatsapp,
            onSelected: () => setState(() => _selectedFilter = ChatAppFilter.whatsapp),
            icon: Icons.chat_rounded,
            activeColor: const Color(0xFF25D366),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('app_filter_sms'),
            label: strings.appSms,
            isSelected: _selectedFilter == ChatAppFilter.sms,
            onSelected: () => setState(() => _selectedFilter = ChatAppFilter.sms),
            icon: Icons.sms_rounded,
            activeColor: const Color(0xFF3B82F6),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('app_filter_telegram'),
            label: strings.appTelegram,
            isSelected: _selectedFilter == ChatAppFilter.telegram,
            onSelected: () => setState(() => _selectedFilter = ChatAppFilter.telegram),
            icon: Icons.send_rounded,
            activeColor: const Color(0xFF0088CC),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            key: const ValueKey('app_filter_signal'),
            label: strings.appSignal,
            isSelected: _selectedFilter == ChatAppFilter.signal,
            onSelected: () => setState(() => _selectedFilter = ChatAppFilter.signal),
            icon: Icons.lock_rounded,
            activeColor: const Color(0xFF3A76F0),
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
    final color = activeColor ?? const Color(0xFF14B8A6);
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

  Widget _buildThreadCard(ChatThread thread, AppStrings strings) {
    final appColor = ChatAppHelper.getAppColor(thread.appPackage, thread.appName);
    final appIcon = ChatAppHelper.getAppIcon(thread.appPackage, thread.appName);
    final appName = ChatAppHelper.getAppDisplayName(
      thread.appPackage,
      thread.appName,
      strings,
    );
    final latest = thread.latestMessage;
    final cleanSender = thread.senderOrChat.isNotEmpty ? thread.senderOrChat : appName;

    // First letter avatar
    final initial = cleanSender.trim().isNotEmpty
        ? cleanSender.trim().characters.first.toUpperCase()
        : '?';

    return Container(
      key: ValueKey('chat_thread_item_${thread.conversationKey}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.6)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatConversationDetailScreen(
                  thread: thread,
                  device: widget.device,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar with App Badge
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: appColor.withValues(alpha: 0.2),
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: appColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E293B),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          appIcon,
                          color: appColor,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Thread Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cleanSender,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTimestamp(latest.dateTime, strings),
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: appColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              appName,
                              style: TextStyle(
                                color: appColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              latest.isOutgoing ? 'You: ${latest.text}' : latest.text,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          strings.noChatsFound,
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
              : strings.searchChatsPlaceholder,
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
                backgroundColor: const Color(0xFF14B8A6),
                foregroundColor: Colors.white,
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

/// Detailed conversation message view for a specific chat thread.
class ChatConversationDetailScreen extends StatelessWidget {
  final ChatThread thread;
  final PairedDevice device;

  const ChatConversationDetailScreen({
    super.key,
    required this.thread,
    required this.device,
  });

  String _formatMessageTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final appColor = ChatAppHelper.getAppColor(thread.appPackage, thread.appName);
    final appIcon = ChatAppHelper.getAppIcon(thread.appPackage, thread.appName);
    final appName = ChatAppHelper.getAppDisplayName(
      thread.appPackage,
      thread.appName,
      strings,
    );
    final cleanSender = thread.senderOrChat.isNotEmpty ? thread.senderOrChat : appName;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: appColor.withValues(alpha: 0.2),
              child: Icon(appIcon, color: appColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cleanSender,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$appName • ${thread.messages.length} messages',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: thread.messages.isEmpty
          ? Center(
              child: Text(
                strings.noMessagesInChat,
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: thread.messages.length,
              itemBuilder: (context, index) {
                final msg = thread.messages[index];
                return _buildMessageBubble(context, msg, cleanSender, appColor);
              },
            ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessageRecord msg,
    String senderTitle,
    Color appColor,
  ) {
    final isOutgoing = msg.isOutgoing;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('chat_bubble_${msg.id}'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOutgoing ? const Color(0xFF6366F1) : const Color(0xFF334155),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isOutgoing ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isOutgoing ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isOutgoing && msg.senderOrChat.isNotEmpty) ...[
              Text(
                msg.senderOrChat,
                style: TextStyle(
                  color: appColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              msg.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMessageTime(msg.dateTime),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 10,
                  ),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
