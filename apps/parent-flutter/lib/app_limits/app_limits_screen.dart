import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../pairing/pairing_repository.dart';
import '../volume/volume_repository.dart';
import 'app_limits_model.dart';
import 'app_limits_repository.dart';
import '../l10n/app_strings.dart';

class AppLimitsScreen extends StatefulWidget {
  final PairedDevice device;
  final String? localIpAddress;

  const AppLimitsScreen({
    super.key,
    required this.device,
    this.localIpAddress,
  });

  @override
  State<AppLimitsScreen> createState() => _AppLimitsScreenState();
}

class _AppLimitsScreenState extends State<AppLimitsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _availableAppsSearchController = TextEditingController();
  String _availableAppsSearchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final repo = Provider.of<AppLimitsRepository>(context, listen: false);
        repo.subscribeToDevice(widget.device.fcmToken);
      }
    });
  }

  @override
  void dispose() {
    _availableAppsSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String? _resolveEffectiveIp(BuildContext context) {
    if (widget.localIpAddress != null && widget.localIpAddress!.isNotEmpty) {
      return widget.localIpAddress;
    }
    try {
      final volRepo = Provider.of<VolumeRepository>(context, listen: false);
      if (volRepo.localIpAddress != null &&
          volRepo.localIpAddress!.isNotEmpty) {
        return volRepo.localIpAddress;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _toggleBlacklist(String packageName, bool isBlocked) async {
    setState(() => _isSaving = true);
    final repo = Provider.of<AppLimitsRepository>(context, listen: false);
    final effectiveIp = _resolveEffectiveIp(context);

    final success = await repo.toggleBlacklist(
      widget.device.fcmToken,
      packageName,
      isBlocked,
      localIpAddress: effectiveIp,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      final strings = context.strings;
      final appName = repo.state.getAppName(packageName);
      final msg = isBlocked
          ? strings.appBlockedInstant(appName)
          : strings.appUnblocked(appName);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _grantBonus(String categoryId, String categoryName, int minutes) async {
    setState(() => _isSaving = true);
    final repo = Provider.of<AppLimitsRepository>(context, listen: false);
    final effectiveIp = _resolveEffectiveIp(context);

    final success = await repo.grantBonusMinutes(
      widget.device.fcmToken,
      categoryId,
      minutes,
      localIpAddress: effectiveIp,
    );

    if (mounted) {
      final strings = context.strings;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? strings.bonusAdded(minutes, categoryName)
                : strings.bonusSyncFailed,
          ),
          backgroundColor:
              success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveCategory(AppCategoryRule rule) async {
    setState(() => _isSaving = true);
    final repo = Provider.of<AppLimitsRepository>(context, listen: false);
    final effectiveIp = _resolveEffectiveIp(context);

    final success = await repo.saveCategory(
      widget.device.fcmToken,
      rule,
      localIpAddress: effectiveIp,
    );

    if (mounted) {
      final strings = context.strings;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? strings.categorySaved(rule.name)
                : strings.categorySaveFailed,
          ),
          backgroundColor:
              success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteCategory(String categoryId, String categoryName) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          strings.deleteCategoryTitle,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          strings.deleteCategoryConfirm(categoryName),
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel, style: const TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_delete_category_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      final repo = Provider.of<AppLimitsRepository>(context, listen: false);
      final effectiveIp = _resolveEffectiveIp(context);

      final success = await repo.deleteCategory(
        widget.device.fcmToken,
        categoryId,
        localIpAddress: effectiveIp,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? strings.categoryDeleted(categoryName)
                  : strings.categoryDeleteFailed,
            ),
            backgroundColor:
                success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final effectiveIp = _resolveEffectiveIp(context);
    final isLanDirect = effectiveIp != null && effectiveIp.isNotEmpty;

    return Consumer<AppLimitsRepository>(
      builder: (context, repo, child) {
        final state = repo.state;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F172A),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.appLimitsTitle,
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
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLanDirect
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLanDirect
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : const Color(0xFF3B82F6).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLanDirect
                                ? const Color(0xFF10B981)
                                : const Color(0xFF3B82F6),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLanDirect ? strings.lanDirect : strings.cloudSync,
                          style: TextStyle(
                            color: isLanDirect
                                ? const Color(0xFF10B981)
                                : const Color(0xFF3B82F6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFEC4899),
              indicatorWeight: 3,
              labelColor: const Color(0xFFEC4899),
              unselectedLabelColor: const Color(0xFF94A3B8),
              tabs: [
                Tab(
                  key: const ValueKey('tab_blacklist'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.block_rounded, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          strings.tabBlacklist(state.blacklistedPackages.length),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  key: const ValueKey('tab_categories'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.hourglass_top_rounded, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          strings.tabCategories(state.categories.length),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  key: const ValueKey('tab_app_history'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history_rounded, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          strings.tabAppHistory,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              TabBarView(
                controller: _tabController,
                children: [
                  _buildBlacklistTab(context, repo),
                  _buildCategoriesTab(context, repo),
                  _buildAppHistoryTab(context, repo),
                ],
              ),
              if (_isSaving)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFEC4899)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 1: SOFORT-SPERRE (BLACKLIST)
  // ==========================================
  Widget _buildBlacklistTab(BuildContext context, AppLimitsRepository repo) {
    final strings = context.strings;
    final state = repo.state;
    final blocked = state.blacklistedPackages;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFEF4444).withValues(alpha: 0.12),
                  const Color(0xFF1E293B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.app_blocking_rounded,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.blacklistBanner,
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Header & Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings.blockedApps(blocked.length),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('btn_add_blacklist'),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(strings.blockApp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _showAddBlacklistModal(context, repo),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Blocked list or empty state
          if (blocked.isEmpty)
            _buildBlacklistEmptyState(context, repo)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: blocked.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final pkg = blocked[index];
                final appName = state.getAppName(pkg);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            appName.isNotEmpty ? appName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pkg,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          strings.statusBlocked,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: ValueKey('btn_unblock_$pkg'),
                        icon: const Icon(
                          Icons.lock_open_rounded,
                          color: Color(0xFF10B981),
                          size: 22,
                        ),
                        tooltip: strings.unblock,
                        onPressed: () => _toggleBlacklist(pkg, false),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 28),
          _buildAvailableAppsSection(context, repo),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildBlacklistEmptyState(BuildContext context, AppLimitsRepository repo) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF10B981),
              size: 40,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.strings.noAppsBlocked,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.strings.noAppsBlockedDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.strings.addAppToBlacklist),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _showAddBlacklistModal(context, repo),
          ),
        ],
      ),
    );
  }

  void _showAddBlacklistModal(BuildContext context, AppLimitsRepository repo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final strings = context.strings;
        return _SearchableAppChecklistModal(
          title: strings.blockApp,
          subtitle: strings.addAppToBlacklist,
          installedApps: repo.state.installedApps,
          selectedPackages: repo.state.blacklistedPackages.toSet(),
          actionColor: const Color(0xFFEF4444),
          actionLabel: strings.blockApp,
          onToggle: (pkg, isSelected) {
            _toggleBlacklist(pkg, isSelected);
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 2: ZEIT-KATEGORIEN (SHARED POOLS)
  // ==========================================
  Widget _buildCategoriesTab(BuildContext context, AppLimitsRepository repo) {
    final strings = context.strings;
    final state = repo.state;
    final categories = state.categories;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                  const Color(0xFF1E293B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: Color(0xFF8B5CF6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Gemeinsame Zeit-Pools für App-Gruppen. Wenn das Tageslimit erreicht ist, pausiert das Tablet alle Apps dieser Kategorie.',
                    style: TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Header & Add Category Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings.timeCategoriesHeader(categories.length),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('btn_new_category'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(strings.newCategory),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _showCategoryEditor(context, repo),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Category Cards
          if (categories.isEmpty)
            _buildCategoriesEmptyState(context, repo)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final category = categories[index];
                return _buildCategoryCard(context, repo, category);
              },
            ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildCategoriesEmptyState(BuildContext context, AppLimitsRepository repo) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              color: Color(0xFF8B5CF6),
              size: 40,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.strings.noCategoriesYet,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.strings.noCategoriesDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.strings.createFirstCategory),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _showCategoryEditor(context, repo),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    AppLimitsRepository repo,
    AppCategoryRule category,
  ) {
    final strings = context.strings;
    final state = repo.state;
    final progress = category.usageProgress;
    final isDepleted = category.isLimitReached;

    // Determine progress color
    Color progressColor = const Color(0xFF8B5CF6);
    if (isDepleted) {
      progressColor = const Color(0xFFEF4444);
    } else if (progress >= 0.8) {
      progressColor = const Color(0xFFF59E0B);
    }

    // App names preview
    final appNames = category.packageNames
        .map((pkg) => state.getAppName(pkg))
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDepleted
              ? const Color(0xFFEF4444).withValues(alpha: 0.5)
              : const Color(0xFF334155),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category Name + Actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.category_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.packageNames.isEmpty
                          ? strings.noAppsInGroup
                          : '${category.packageNames.length} ${strings.assignedApps}',
                      style: TextStyle(
                        color: category.packageNames.isEmpty
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('btn_edit_category_${category.id}'),
                icon: const Icon(Icons.tune_rounded, color: Color(0xFF94A3B8), size: 20),
                tooltip: strings.editCategory,
                onPressed: () => _showCategoryEditor(context, repo, existing: category),
              ),
              IconButton(
                key: ValueKey('btn_delete_category_${category.id}'),
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                tooltip: strings.deleteCategoryTitle,
                onPressed: () => _deleteCategory(category.id, category.name),
              ),
            ],
          ),

          if (appNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: appNames.take(4).map((name) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList()
                ..addAll([
                  if (appNames.length > 4)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${appNames.length - 4} weitere',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ]),
            ),
          ],

          const SizedBox(height: 16),

          // Daily limit & Remaining time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '${strings.dailyLimit}: ${category.dailyLimitMinutes} Min.',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                  if (category.bonusMinutes > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+${category.bonusMinutes}m Bonus',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                isDepleted
                    ? 'Limit erreicht'
                    : '${category.remainingMinutes} Min. verbleibend',
                style: TextStyle(
                  color: isDepleted
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF0F172A),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),

          const SizedBox(height: 6),

          // Usage details text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${category.usedMinutes} von ${category.totalAllowedMinutes} Min. heute genutzt',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  color: progressColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 12),

          // Quick Bonus Buttons: „+15 Min.“ and „+30 Min.“
          Row(
            children: [
              Text(
                '${strings.bonusToday}:',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                key: ValueKey('btn_bonus_15_${category.id}'),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
                label: Text(strings.add15MinBonus),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: BorderSide(
                    color: const Color(0xFF10B981).withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _grantBonus(category.id, category.name, 15),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: ValueKey('btn_bonus_30_${category.id}'),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
                label: Text(strings.add30MinBonus),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: BorderSide(
                    color: const Color(0xFF10B981).withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _grantBonus(category.id, category.name, 30),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCategoryEditor(
    BuildContext context,
    AppLimitsRepository repo, {
    AppCategoryRule? existing,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _CategoryEditorModal(
          existing: existing,
          installedApps: repo.state.installedApps,
          onSave: (rule) {
            Navigator.of(ctx).pop();
            _saveCategory(rule);
          },
        );
      },
    );
  }

  Widget _buildAvailableAppsSection(BuildContext context, AppLimitsRepository repo) {
    final strings = context.strings;
    final state = repo.state;

    // Filter out Family Link allowed apps like Spotify, system apps, and already blocked apps
    final apps = state.installedApps.where((app) {
      final pkg = app.packageName.toLowerCase();
      if (pkg == 'com.spotify.music') return false;
      if (pkg == 'com.familylink.buddy.child') return false;
      if (pkg.contains('dialer') || pkg.contains('.phone')) return false;
      if (pkg == 'com.android.settings' || pkg == 'com.google.android.settings') return false;
      if (state.isBlacklisted(app.packageName)) return false;

      if (_availableAppsSearchQuery.isNotEmpty) {
        final q = _availableAppsSearchQuery.toLowerCase();
        final nameMatches = app.appName.toLowerCase().contains(q);
        final pkgMatches = pkg.contains(q);
        if (!nameMatches && !pkgMatches) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              strings.availableApps,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
              ),
              child: Text(
                '${apps.length}',
                style: const TextStyle(
                  color: Color(0xFF818CF8),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          strings.availableAppsDesc,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        // Search bar
        TextField(
          key: const ValueKey('input_search_available_apps'),
          controller: _availableAppsSearchController,
          onChanged: (val) {
            setState(() {
              _availableAppsSearchQuery = val.trim();
            });
          },
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: strings.searchAvailableApps,
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF818CF8), size: 20),
            suffixIcon: _availableAppsSearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 18),
                    onPressed: () {
                      _availableAppsSearchController.clear();
                      setState(() {
                        _availableAppsSearchQuery = '';
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF1E293B),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Color(0xFF818CF8)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (apps.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                strings.noInstalledAppsFound,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: apps.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final app = apps[index];
              final isBlocked = state.isBlacklisted(app.packageName);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBlocked
                        ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isBlocked
                            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                            : const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isBlocked ? const Color(0xFFEF4444) : const Color(0xFF818CF8),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.appName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            app.packageName,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isBlocked)
                      OutlinedButton(
                        key: ValueKey('btn_toggle_block_${app.packageName}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _toggleBlacklist(app.packageName, false),
                        child: Text(
                          strings.unblock,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        key: ValueKey('btn_toggle_block_${app.packageName}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.block_rounded, size: 14),
                        label: Text(
                          strings.blockApp,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _toggleBlacklist(app.packageName, true),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      );
  }

  // ==========================================
  // TAB 3: APP-HISTORIE (5 TAGE)
  // ==========================================
  Widget _buildAppHistoryTab(BuildContext context, AppLimitsRepository repo) {
    final strings = context.strings;
    final state = repo.state;
    final history = repo.appHistory;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6366F1).withValues(alpha: 0.15),
                  const Color(0xFF1E293B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: Color(0xFF818CF8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.appHistoryTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.appHistorySubtitle,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('btn_refresh_history'),
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF818CF8)),
                  tooltip: strings.refreshTooltip,
                  onPressed: () {
                    final effectiveIp = _resolveEffectiveIp(context);
                    repo.fetchAppHistory(
                      widget.device.fcmToken,
                      localIpAddress: effectiveIp,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (history.isEmpty)
            Container(
              key: const ValueKey('empty_app_history'),
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    size: 48,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.noAppHistory,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final record = history[index];
                final isBlocked = state.isBlacklisted(record.packageName);
                final displayName = record.label.isNotEmpty
                    ? record.label
                    : state.getAppName(record.packageName);

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isBlocked
                          ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isBlocked
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : const Color(0xFF6366F1).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: isBlocked
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF818CF8),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTimestamp(context, record.timestamp),
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              record.packageName,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isBlocked)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            strings.statusBlocked,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          key: ValueKey('btn_block_history_${record.packageName}'),
                          icon: const Icon(Icons.block_rounded, size: 14),
                          label: Text(strings.blockApp),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _toggleBlacklist(record.packageName, true),
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
  }

  String _formatTimestamp(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final timeStr = '${pad2(dt.hour)}:${pad2(dt.minute)}';
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(itemDate).inDays;

    if (diffDays == 0) {
      return '${context.strings.todayFilter}, $timeStr';
    } else if (diffDays == 1) {
      final yLabel = context.strings.languageCode == 'de' ? 'Gestern' : 'Yesterday';
      return '$yLabel, $timeStr';
    } else {
      return '${pad2(dt.day)}.${pad2(dt.month)}. $timeStr';
    }
  }
}

// ==========================================
// SEARCHABLE APP CHECKLIST MODAL (BOTTOM SHEET)
// ==========================================
class _SearchableAppChecklistModal extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<InstalledAppInfo> installedApps;
  final Set<String> selectedPackages;
  final Color actionColor;
  final String actionLabel;
  final void Function(String packageName, bool isSelected) onToggle;

  const _SearchableAppChecklistModal({
    required this.title,
    required this.subtitle,
    required this.installedApps,
    required this.selectedPackages,
    required this.actionColor,
    required this.actionLabel,
    required this.onToggle,
  });

  @override
  State<_SearchableAppChecklistModal> createState() =>
      _SearchableAppChecklistModalState();
}

class _SearchableAppChecklistModalState
    extends State<_SearchableAppChecklistModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedPackages);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase().trim();
    final filtered = widget.installedApps.where((app) {
      if (query.isEmpty) return true;
      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),

            // Search Bar
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: context.strings.searchApps,
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.actionColor),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // App Checklist
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          context.strings.noInstalledAppsFound,
                          style: const TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: Color(0xFF334155),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final app = filtered[index];
                        final isChecked = _selected.contains(app.packageName);

                        return CheckboxListTile(
                          key: ValueKey('checklist_item_${app.packageName}'),
                          value: isChecked,
                          activeColor: widget.actionColor,
                          checkColor: Colors.white,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            app.appName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            app.packageName,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                          secondary: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Center(
                              child: Text(
                                app.appName.isNotEmpty
                                    ? app.appName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: widget.actionColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            final nextState = val ?? false;
                            setState(() {
                              if (nextState) {
                                _selected.add(app.packageName);
                              } else {
                                _selected.remove(app.packageName);
                              }
                            });
                            widget.onToggle(app.packageName, nextState);
                          },
                        );
                      },
                    ),
            ),

            const SizedBox(height: 14),

            // Done button
            ElevatedButton(
              key: const ValueKey('btn_modal_done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.strings.confirm, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// CATEGORY EDITOR MODAL (BOTTOM SHEET)
// ==========================================
class _CategoryEditorModal extends StatefulWidget {
  final AppCategoryRule? existing;
  final List<InstalledAppInfo> installedApps;
  final void Function(AppCategoryRule rule) onSave;

  const _CategoryEditorModal({
    this.existing,
    required this.installedApps,
    required this.onSave,
  });

  @override
  State<_CategoryEditorModal> createState() => _CategoryEditorModalState();
}

class _CategoryEditorModalState extends State<_CategoryEditorModal> {
  late TextEditingController _nameCtrl;
  late int _limitMinutes;
  late Set<String> _selectedPackages;
  final TextEditingController _searchCtrl = TextEditingController();

  static const List<int> _quickMinuteOptions = [15, 30, 45, 60, 90, 120, 180];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _limitMinutes = widget.existing?.dailyLimitMinutes ?? 60;
    _selectedPackages = Set.from(widget.existing?.packageNames ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.categoryNameValidator),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final id = widget.existing?.id ?? const Uuid().v4();
    final rule = AppCategoryRule(
      id: id,
      name: name,
      packageNames: _selectedPackages.toList(),
      dailyLimitMinutes: _limitMinutes,
      bonusMinutes: widget.existing?.bonusMinutes ?? 0,
      usedMinutes: widget.existing?.usedMinutes ?? 0,
    );

    widget.onSave(rule);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final query = _searchCtrl.text.toLowerCase().trim();
    final filtered = widget.installedApps.where((app) {
      if (query.isEmpty) return true;
      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              isNew ? context.strings.newTimeCategory : context.strings.editCategory,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Category Name Input
            TextField(
              key: const ValueKey('input_category_name'),
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: context.strings.categoryNameLabel,
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: Color(0xFF8B5CF6)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Daily Limit Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${context.strings.dailyLimit}:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppCategoryRule.formatMinutes(_limitMinutes),
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickMinuteOptions.map((mins) {
                  final isSelected = _limitMinutes == mins;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('chip_limit_$mins'),
                      label: Text('$mins Min.'),
                      selected: isSelected,
                      selectedColor: const Color(0xFF8B5CF6),
                      backgroundColor: const Color(0xFF0F172A),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _limitMinutes = mins);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 18),

            // Select Apps Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    context.strings.selectAppsForCategory,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedPackages.length} ausgewählt',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Filter apps TextField
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: context.strings.searchApps,
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 18),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: Color(0xFF8B5CF6)),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            // Apps checklist
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const Divider(
                  color: Color(0xFF334155),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final app = filtered[index];
                  final isChecked = _selectedPackages.contains(app.packageName);

                  return CheckboxListTile(
                    key: ValueKey('cat_app_check_${app.packageName}'),
                    value: isChecked,
                    activeColor: const Color(0xFF8B5CF6),
                    checkColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      app.appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      app.packageName,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedPackages.add(app.packageName);
                        } else {
                          _selectedPackages.remove(app.packageName);
                        }
                      });
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Save and Cancel buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.strings.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('btn_save_category'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _submit,
                    child: Text(
                      context.strings.save,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
