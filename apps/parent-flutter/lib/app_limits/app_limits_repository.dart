import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_limits_model.dart';

class AppLimitsRepository extends ChangeNotifier {
  final FirebaseFirestore? _firestore;
  final http.Client? _httpClient;
  StreamSubscription<DocumentSnapshot>? _subscription;

  AppLimitsState _state = const AppLimitsState(
    installedApps: defaultInstalledApps,
    categories: defaultCategories,
  );

  AppLimitsRepository({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
  })  : _firestore = firestore,
        _httpClient = httpClient;

  AppLimitsState get state => _state;

  @visibleForTesting
  set state(AppLimitsState value) {
    _state = value;
    notifyListeners();
  }

  FirebaseFirestore? get firestore {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
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
  ];

  /// Subscribes to real-time updates for app limits, blacklist, and installed apps
  void subscribeToDevice(String childFcmToken) {
    _subscription?.cancel();
    if (childFcmToken.isEmpty || childFcmToken == 'emulator') return;

    final fs = firestore;
    if (fs == null) return;

    try {
      _subscription = fs
          .collection('pairings')
          .doc(childFcmToken)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            handleSnapshotData(data);
          }
        }
      }, onError: (e) {
        debugPrint('AppLimitsRepository subscription error: $e');
      });
    } catch (e) {
      debugPrint('AppLimitsRepository subscribe error: $e');
    }
  }

  /// Parses Firestore snapshot data and updates state
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
              // If not already in installed apps, add it
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

    // Ensure we keep default apps if none were discovered
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

  /// Saves the complete app limit configuration:
  /// 1. Direct HTTP POST to child tablet LAN server http://$localIpAddress:8085/set_app_rules
  /// 2. Firestore document update to pairings/$childFcmToken
  Future<bool> saveRules(
    String childFcmToken, {
    String? localIpAddress,
  }) async {
    bool directSuccess = false;

    // Direct HTTP push
    if (localIpAddress != null && localIpAddress.isNotEmpty) {
      try {
        final url = Uri.parse('http://$localIpAddress:8085/set_app_rules');
        final payload = jsonEncode({
          'blacklistedPackages': _state.blacklistedPackages,
          'categories': _state.categories.map((c) => c.toJson()).toList(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        final response = _httpClient != null
            ? await _httpClient
                .post(
                  url,
                  headers: {'Content-Type': 'application/json'},
                  body: payload,
                )
                .timeout(const Duration(seconds: 2))
            : await http
                .post(
                  url,
                  headers: {'Content-Type': 'application/json'},
                  body: payload,
                )
                .timeout(const Duration(seconds: 2));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          directSuccess = true;
          debugPrint('Direct HTTP set_app_rules succeeded ($localIpAddress)');
        } else {
          debugPrint('Direct HTTP set_app_rules returned status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Direct HTTP set_app_rules error: $e');
      }
    }

    // Firestore dual-write / sync
    bool firestoreSuccess = false;
    final fs = firestore;
    if (fs != null && childFcmToken.isNotEmpty) {
      try {
        final categoriesJson =
            _state.categories.map((c) => c.toJson()).toList();
        await fs.collection('pairings').doc(childFcmToken).set({
          'appLimits': {
            'blacklistedPackages': _state.blacklistedPackages,
            'categories': categoriesJson,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'blacklistedPackages': _state.blacklistedPackages,
          'appCategories': categoriesJson,
        }, SetOptions(merge: true));
        firestoreSuccess = true;
      } catch (e) {
        debugPrint('Firestore saveRules error: $e');
      }
    }

    return directSuccess || firestoreSuccess;
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
