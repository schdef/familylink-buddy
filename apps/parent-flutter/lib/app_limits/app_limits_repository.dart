import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_limits_model.dart';

class AppLimitsRepository extends ChangeNotifier {
  final http.Client? _httpClient;
  final SharedPreferences? _prefs;

  AppLimitsState _state = const AppLimitsState(
    installedApps: defaultInstalledApps,
    categories: defaultCategories,
  );

  List<AppOpeningRecord> _appHistory = [];
  Timer? _pollingTimer;
  bool _isDisposed = false;

  AppLimitsRepository({
    http.Client? httpClient,
    SharedPreferences? prefs,
    dynamic firestore,
  })  : _httpClient = httpClient,
        _prefs = prefs;

  AppLimitsState get state => _state;
  List<AppOpeningRecord> get appHistory => _appHistory;

  @visibleForTesting
  set state(AppLimitsState value) {
    _state = value;
    notifyListeners();
  }

  @visibleForTesting
  set appHistory(List<AppOpeningRecord> value) {
    _appHistory = value;
    notifyListeners();
  }

  static const List<InstalledAppInfo> defaultInstalledApps = [
    InstalledAppInfo(
      packageName: 'com.google.android.apps.chromecast.app',
      appName: 'Google Home',
    ),
    InstalledAppInfo(
      packageName: 'com.google.android.apps.youtube.kids',
      appName: 'YouTube Kids',
    ),
    InstalledAppInfo(
      packageName: 'com.roblox.client',
      appName: 'Roblox',
    ),
    InstalledAppInfo(
      packageName: 'com.mojang.minecraftpe',
      appName: 'Minecraft',
    ),
    InstalledAppInfo(
      packageName: 'com.supercell.brawlstars',
      appName: 'Brawl Stars',
    ),
    InstalledAppInfo(
      packageName: 'com.android.chrome',
      appName: 'Google Chrome',
    ),
    InstalledAppInfo(
      packageName: 'com.netflix.ninja',
      appName: 'Netflix',
    ),
    InstalledAppInfo(
      packageName: 'com.zhiliaoapp.musically',
      appName: 'TikTok',
    ),
    InstalledAppInfo(
      packageName: 'com.disney.disneyplus',
      appName: 'Disney+',
    ),
    InstalledAppInfo(
      packageName: 'com.spotify.music',
      appName: 'Spotify',
    ),
  ];

  static const List<AppCategoryRule> defaultCategories = [
    AppCategoryRule(
      id: 'cat-games',
      name: 'Spiele',
      packageNames: [
        'com.roblox.client',
        'com.mojang.minecraftpe',
        'com.supercell.brawlstars',
      ],
      dailyLimitMinutes: 60,
      usedMinutes: 0,
      bonusMinutes: 0,
    ),
    AppCategoryRule(
      id: 'cat-videos',
      name: 'Videos',
      packageNames: [
        'com.google.android.apps.youtube.kids',
        'com.netflix.ninja',
        'com.disney.disneyplus',
      ],
      dailyLimitMinutes: 45,
      usedMinutes: 0,
      bonusMinutes: 0,
    ),
    AppCategoryRule(
      id: 'cat-learning',
      name: 'Lernen & Wissen',
      packageNames: [
        'com.google.android.apps.chromecast.app',
        'com.android.chrome',
      ],
      dailyLimitMinutes: 120,
      usedMinutes: 0,
      bonusMinutes: 0,
    ),
  ];

  static String blacklistKey(String childToken) => 'key_app_limits_blacklist_$childToken';
  static String categoriesKey(String childToken) => 'key_app_limits_categories_$childToken';
  static String appHistoryKey(String childToken) => 'key_app_history_$childToken';

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('AppLimitsRepository: error getting SharedPreferences: $e');
      return null;
    }
  }

  Future<void> _loadCache(String childToken) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;

      // 1. Blacklist
      List<String>? blacklist = prefs.getStringList(blacklistKey(childToken));
      if (blacklist == null) {
        final raw = prefs.getString(blacklistKey(childToken));
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              blacklist = decoded.map((e) => e.toString()).toList();
            }
          } catch (_) {}
        }
      }

      // 2. Categories
      List<AppCategoryRule>? categories;
      final rawCategories = prefs.getString(categoriesKey(childToken));
      if (rawCategories != null && rawCategories.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawCategories);
          if (decoded is List) {
            categories = decoded
                .map((e) => AppCategoryRule.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
        } catch (e) {
          debugPrint('Error decoding cached categories: $e');
        }
      }

      // 3. App History
      List<AppOpeningRecord>? history;
      final rawHistory = prefs.getString(appHistoryKey(childToken));
      if (rawHistory != null && rawHistory.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawHistory);
          if (decoded is List) {
            history = decoded
                .map((e) => AppOpeningRecord.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
        } catch (e) {
          debugPrint('Error decoding cached app history: $e');
        }
      }

      bool stateChanged = false;
      var newState = _state;

      if (blacklist != null) {
        newState = newState.copyWith(blacklistedPackages: blacklist);
        stateChanged = true;
      }
      if (categories != null && categories.isNotEmpty) {
        newState = newState.copyWith(categories: categories);
        stateChanged = true;
      }
      if (stateChanged) {
        _state = newState;
        notifyListeners();
      }

      if (history != null && history.isNotEmpty) {
        _appHistory = history;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AppLimitsRepository: _loadCache error: $e');
    }
  }

  Future<void> _saveCache(String childToken) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;

      await prefs.setStringList(blacklistKey(childToken), _state.blacklistedPackages);
      final categoriesJson = jsonEncode(_state.categories.map((c) => c.toJson()).toList());
      await prefs.setString(categoriesKey(childToken), categoriesJson);
    } catch (e) {
      debugPrint('AppLimitsRepository: _saveCache error: $e');
    }
  }

  Future<void> _saveHistoryCache(String childToken) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;

      final historyJson = jsonEncode(_appHistory.map((h) => h.toJson()).toList());
      await prefs.setString(appHistoryKey(childToken), historyJson);
    } catch (e) {
      debugPrint('AppLimitsRepository: _saveHistoryCache error: $e');
    }
  }

  @visibleForTesting
  Future<void> loadCache(String childToken) => _loadCache(childToken);

  @visibleForTesting
  Future<void> saveCache(String childToken) => _saveCache(childToken);

  @visibleForTesting
  Future<void> saveHistoryCache(String childToken) => _saveHistoryCache(childToken);

  String _resolveHost(String? localIpAddress, String childToken) {
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      return localIpAddress;
    }
    if (childToken == 'emulator') {
      return '10.0.2.2';
    }
    if (childToken.contains('.')) {
      return childToken;
    }
    return '10.0.2.2';
  }

  @visibleForTesting
  Timer? get pollingTimer => _pollingTimer;

  /// Starts listening to device rules over LAN
  Future<void> subscribeToDevice(String childFcmToken, {String? localIpAddress}) async {
    await _loadCache(childFcmToken);
    fetchRules(childFcmToken, localIpAddress: localIpAddress);
    fetchInstalledApps(childFcmToken, localIpAddress: localIpAddress);
    fetchAppHistory(childFcmToken, localIpAddress: localIpAddress);

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => fetchRules(childFcmToken, localIpAddress: localIpAddress),
    );
  }

  /// Stops background polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopPolling();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// Fetches app rules from child device via GET /get_app_rules over LAN
  Future<bool> fetchRules(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/get_app_rules');
      final client = _httpClient;
      final response = client != null
          ? await client.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3))
          : await http.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rules = data['rules'] as Map<String, dynamic>? ?? {};
        final blacklist = (rules['blacklistedPackages'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            _state.blacklistedPackages;

        final rawCats = rules['categories'] as List<dynamic>?;
        final bonusMap = data['bonusMinutes'] as Map<String, dynamic>? ?? {};
        final usageMap = data['categoryUsageSeconds'] as Map<String, dynamic>? ?? {};

        List<AppCategoryRule> categories;
        if (rawCats != null) {
          categories = rawCats.map((c) {
            final cat = AppCategoryRule.fromJson(Map<String, dynamic>.from(c as Map));
            final bonus = (bonusMap[cat.id] as num?)?.toInt() ?? cat.bonusMinutes;
            final usedSec = (usageMap[cat.id] as num?)?.toInt() ?? (cat.usedMinutes * 60);
            return cat.copyWith(bonusMinutes: bonus, usedMinutes: (usedSec / 60).round());
          }).toList();
        } else {
          categories = _state.categories;
        }

        _state = _state.copyWith(
          blacklistedPackages: blacklist,
          categories: categories,
          lastUpdated: DateTime.now(),
        );
        notifyListeners();
        await _saveCache(childFcmToken);
        return true;
      }
    } catch (e) {
      debugPrint('AppLimitsRepository: fetchRules error: $e');
    }
    return false;
  }

  /// Fetches installed apps from child device via GET /installed_apps over LAN
  Future<bool> fetchInstalledApps(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/installed_apps');
      final client = _httpClient;
      final response = client != null
          ? await client.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3))
          : await http.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawApps = data['installedApps'] as List<dynamic>?;
        if (rawApps != null) {
          final apps = rawApps.map((a) {
            final map = Map<String, dynamic>.from(a as Map);
            return InstalledAppInfo(
              packageName: map['packageName'] as String? ?? '',
              appName: map['label'] as String? ?? map['appName'] as String? ?? '',
            );
          }).toList();
          _state = _state.copyWith(installedApps: apps);
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('AppLimitsRepository: fetchInstalledApps error: $e');
    }
    return false;
  }

  /// Fetches 5-day (or specified days) app opening history via GET /app_history?days=$days over LAN
  Future<List<AppOpeningRecord>> fetchAppHistory(
    String childFcmToken, {
    String? localIpAddress,
    int days = 5,
  }) async {
    try {
      final host = _resolveHost(localIpAddress, childFcmToken);
      final url = Uri.parse('http://$host:8085/app_history?days=$days');
      final client = _httpClient;
      final response = client != null
          ? await client.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3))
          : await http.get(url, headers: {'X-Buddy-Token': childFcmToken}).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawHistory = data['history'] as List<dynamic>?;
        if (rawHistory != null) {
          final list = rawHistory.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            return AppOpeningRecord.fromJson(map);
          }).toList();
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          _appHistory = list;
          notifyListeners();
          await _saveHistoryCache(childFcmToken);
          return list;
        }
      }
    } catch (e) {
      debugPrint('AppLimitsRepository: fetchAppHistory error: $e');
    }
    return _appHistory;
  }

  /// Parses snapshot data for backward compatibility in unit tests
  void handleSnapshotData(Map<String, dynamic> data) {
    // 1. Blacklist
    List<String> blacklist = _state.blacklistedPackages;
    if (data.containsKey('blacklistedPackages')) {
      final list = data['blacklistedPackages'] as List<dynamic>?;
      if (list != null) {
        blacklist = list.map((e) => e.toString()).toList();
      }
    } else if (data['appLimits'] is Map &&
        (data['appLimits'] as Map).containsKey('blacklistedPackages')) {
      final list =
          (data['appLimits'] as Map)['blacklistedPackages'] as List<dynamic>?;
      if (list != null) {
        blacklist = list.map((e) => e.toString()).toList();
      }
    }

    // 2. Installed Apps
    List<InstalledAppInfo> apps = List.from(_state.installedApps);
    if (data.containsKey('installedApps')) {
      final appList = data['installedApps'] as List<dynamic>?;
      if (appList != null && appList.isNotEmpty) {
        apps = appList
            .map((e) =>
                InstalledAppInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    }

    // 3. App Usages
    Map<String, int> usages = {};
    if (data.containsKey('appUsages')) {
      final rawUsages = data['appUsages'];
      if (rawUsages is List) {
        for (final item in rawUsages) {
          if (item is Map) {
            final pkg = (item['packageName'] ?? item['pkg'] ?? '').toString();
            final name = (item['appName'] ?? item['name'] ?? '').toString();
            final used = (item['usedMinutes'] ?? item['used'] ?? 0) as num;
            if (pkg.isNotEmpty) {
              usages[pkg] = used.toInt();
              if (!apps.any((a) => a.packageName == pkg)) {
                apps.add(InstalledAppInfo(
                  packageName: pkg,
                  appName: name.isNotEmpty ? name : pkg,
                ));
              }
            }
          }
        }
      } else if (rawUsages is Map) {
        usages = rawUsages.map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        );
      }
    }

    if (apps.isEmpty) {
      apps = List.from(defaultInstalledApps);
    }

    // 4. Categories
    List<AppCategoryRule> categories = List.from(_state.categories);
    dynamic rawCategories = data['appCategories'];
    if (rawCategories == null && data['appLimits'] is Map) {
      rawCategories = (data['appLimits'] as Map)['categories'];
    }

    if (rawCategories is List && rawCategories.isNotEmpty) {
      categories = rawCategories
          .map((e) =>
              AppCategoryRule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else if (categories.isEmpty) {
      categories = List.from(defaultCategories);
    }

    // Calculate each category's usedMinutes by summing its member apps' usage
    if (usages.isNotEmpty) {
      categories = categories.map((cat) {
        int totalUsed = 0;
        for (final pkg in cat.packageNames) {
          totalUsed += usages[pkg] ?? 0;
        }
        return cat.copyWith(usedMinutes: totalUsed);
      }).toList();
    }

    _state = _state.copyWith(
      blacklistedPackages: blacklist,
      categories: categories,
      installedApps: apps,
      appUsages: usages,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
  }

  /// Saves the complete app limit configuration via POST /set_app_rules over LAN
  Future<bool> saveRules(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    await _saveCache(childFcmToken);
    final host = _resolveHost(localIpAddress, childFcmToken);
    try {
      final url = Uri.parse('http://$host:8085/set_app_rules');
      final payload = jsonEncode({
        'blacklistedPackages': _state.blacklistedPackages,
        'categories': _state.categories.map((c) => c.toJson()).toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final client = _httpClient;
      final response = client != null
          ? await client.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: payload,
            ).timeout(const Duration(seconds: 3))
          : await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: payload,
            ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Direct HTTP set_app_rules succeeded ($host)');
        return true;
      } else {
        debugPrint('Direct HTTP set_app_rules returned status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Direct HTTP set_app_rules error: $e');
      return false;
    }
  }

  /// Toggles an app's blocked status (Tab 1: Sofort-Sperre)
  Future<bool> toggleBlacklist(
    String childFcmToken,
    String packageName,
    bool isBlocked, {
    String? localIpAddress,
  }) async {
    final list = List<String>.from(_state.blacklistedPackages);
    if (isBlocked) {
      if (!list.contains(packageName)) {
        list.add(packageName);
      }
    } else {
      list.remove(packageName);
    }

    _state = _state.copyWith(blacklistedPackages: list);
    notifyListeners();
    await _saveCache(childFcmToken);

    final host = _resolveHost(localIpAddress, childFcmToken);
    try {
      final url = Uri.parse(
        'http://$host:8085/toggle_block_app?package=${Uri.encodeQueryComponent(packageName)}&blocked=$isBlocked',
      );
      final payload = jsonEncode({
        'package': packageName,
        'blocked': isBlocked,
      });

      final client = _httpClient;
      final response = client != null
          ? await client.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: payload,
            ).timeout(const Duration(seconds: 3))
          : await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: payload,
            ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            final rawList = data['blacklistedPackages'] ??
                (data['rules'] is Map<String, dynamic>
                    ? (data['rules'] as Map<String, dynamic>)['blacklistedPackages']
                    : null);
            if (rawList is List) {
              final updatedList = rawList.map((e) => e.toString()).toList();
              _state = _state.copyWith(blacklistedPackages: updatedList);
              await _saveCache(childFcmToken);
              notifyListeners();
            }
          }
        } catch (e) {
          debugPrint('toggle_block_app JSON decode error: $e');
        }
        return true;
      } else {
        debugPrint('toggle_block_app returned status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('toggle_block_app error: $e');
    }

    // Fall back to saveRules for backward compatibility
    return saveRules(childFcmToken, localIpAddress: localIpAddress);
  }

  /// Grants quick bonus minutes to a category on the fly (+15 Min. / +30 Min.)
  Future<bool> grantBonusMinutes(
    String childFcmToken,
    String categoryId,
    int bonusMinutesToAdd, {
    String? localIpAddress,
  }) async {
    final updatedCategories = _state.categories.map((c) {
      if (c.id == categoryId) {
        return c.copyWith(bonusMinutes: c.bonusMinutes + bonusMinutesToAdd);
      }
      return c;
    }).toList();

    _state = _state.copyWith(categories: updatedCategories);
    notifyListeners();

    final host = _resolveHost(localIpAddress, childFcmToken);
    try {
      final url = Uri.parse('http://$host:8085/add_bonus_minutes');
      final payload = jsonEncode({
        'categoryId': categoryId,
        'minutes': bonusMinutesToAdd,
      });

      final client = _httpClient;
      final response = client != null
          ? await client.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: payload,
            ).timeout(const Duration(seconds: 3))
          : await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'X-Buddy-Token': childFcmToken,
              },
              body: payload,
            ).timeout(const Duration(seconds: 3));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _saveCache(childFcmToken);
        return true;
      }
    } catch (e) {
      debugPrint('add_bonus_minutes error: $e');
    }

    return saveRules(childFcmToken, localIpAddress: localIpAddress);
  }

  /// Saves or updates a category rule
  Future<bool> saveCategory(
    String childFcmToken,
    AppCategoryRule category, {
    String? localIpAddress,
  }) async {
    final list = List<AppCategoryRule>.from(_state.categories);
    final idx = list.indexWhere((c) => c.id == category.id);
    if (idx >= 0) {
      list[idx] = category;
    } else {
      list.add(category);
    }

    _state = _state.copyWith(categories: list);
    notifyListeners();

    return saveRules(childFcmToken, localIpAddress: localIpAddress);
  }

  /// Deletes a category rule
  Future<bool> deleteCategory(
    String childFcmToken,
    String categoryId, {
    String? localIpAddress,
  }) async {
    final list = _state.categories.where((c) => c.id != categoryId).toList();
    _state = _state.copyWith(categories: list);
    notifyListeners();

    return saveRules(childFcmToken, localIpAddress: localIpAddress);
  }

  /// Updates installed apps list (e.g. from tests or child report)
  void setInstalledApps(List<InstalledAppInfo> apps) {
    _state = _state.copyWith(installedApps: apps);
    notifyListeners();
  }
}
