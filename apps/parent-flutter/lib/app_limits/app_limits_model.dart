import 'package:flutter/foundation.dart';

@immutable
class InstalledAppInfo {
  final String packageName;
  final String appName;
  final String? iconBase64;

  const InstalledAppInfo({
    required this.packageName,
    required this.appName,
    this.iconBase64,
  });

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'appName': appName,
        if (iconBase64 != null) 'iconBase64': iconBase64,
      };

  factory InstalledAppInfo.fromJson(Map<String, dynamic> json) {
    return InstalledAppInfo(
      packageName: (json['packageName'] ?? json['pkg'] ?? '').toString(),
      appName: (json['appName'] ?? json['name'] ?? '').toString(),
      iconBase64: json['iconBase64'] as String?,
    );
  }

  InstalledAppInfo copyWith({
    String? packageName,
    String? appName,
    String? iconBase64,
  }) {
    return InstalledAppInfo(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      iconBase64: iconBase64 ?? this.iconBase64,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstalledAppInfo &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          appName == other.appName &&
          iconBase64 == other.iconBase64;

  @override
  int get hashCode =>
      packageName.hashCode ^ appName.hashCode ^ (iconBase64?.hashCode ?? 0);

  @override
  String toString() => 'InstalledAppInfo(name: $appName, pkg: $packageName)';
}

@immutable
class AppCategoryRule {
  final String id;
  final String name;
  final List<String> packageNames;
  final int dailyLimitMinutes;
  final int bonusMinutes;
  final int usedMinutes;
  final String? iconName;
  final int? colorHex;

  const AppCategoryRule({
    required this.id,
    required this.name,
    this.packageNames = const [],
    this.dailyLimitMinutes = 60,
    this.bonusMinutes = 0,
    this.usedMinutes = 0,
    this.iconName,
    this.colorHex,
  });

  int get totalAllowedMinutes => dailyLimitMinutes + bonusMinutes;

  int get remainingMinutes {
    final remaining = totalAllowedMinutes - usedMinutes;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isLimitReached =>
      totalAllowedMinutes > 0 && usedMinutes >= totalAllowedMinutes;

  double get usageProgress {
    if (totalAllowedMinutes <= 0) return 0.0;
    final progress = usedMinutes / totalAllowedMinutes;
    if (progress < 0.0) return 0.0;
    if (progress > 1.0) return 1.0;
    return progress;
  }

  String get dailyLimitFormatted => formatMinutes(dailyLimitMinutes);
  String get remainingFormatted => formatMinutes(remainingMinutes);
  String get usedFormatted => formatMinutes(usedMinutes);
  String get totalAllowedFormatted => formatMinutes(totalAllowedMinutes);

  static String formatMinutes(int minutes) {
    if (minutes <= 0) return '0 Min.';
    if (minutes < 60) return '$minutes Min.';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) {
      return hours == 1 ? '1 Std.' : '$hours Std.';
    }
    return '$hours Std. $remainder Min.';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'packageNames': packageNames,
        'dailyLimitMinutes': dailyLimitMinutes,
        'bonusMinutes': bonusMinutes,
        'usedMinutes': usedMinutes,
        if (iconName != null) 'iconName': iconName,
        if (colorHex != null) 'colorHex': colorHex,
      };

  factory AppCategoryRule.fromJson(Map<String, dynamic> json) {
    return AppCategoryRule(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      packageNames: (json['packageNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      dailyLimitMinutes: (json['dailyLimitMinutes'] as num?)?.toInt() ?? 60,
      bonusMinutes: (json['bonusMinutes'] as num?)?.toInt() ?? 0,
      usedMinutes: (json['usedMinutes'] as num?)?.toInt() ?? 0,
      iconName: json['iconName'] as String?,
      colorHex: (json['colorHex'] as num?)?.toInt(),
    );
  }

  AppCategoryRule copyWith({
    String? id,
    String? name,
    List<String>? packageNames,
    int? dailyLimitMinutes,
    int? bonusMinutes,
    int? usedMinutes,
    String? iconName,
    int? colorHex,
  }) {
    return AppCategoryRule(
      id: id ?? this.id,
      name: name ?? this.name,
      packageNames: packageNames ?? this.packageNames,
      dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
      bonusMinutes: bonusMinutes ?? this.bonusMinutes,
      usedMinutes: usedMinutes ?? this.usedMinutes,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppCategoryRule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          listEquals(packageNames, other.packageNames) &&
          dailyLimitMinutes == other.dailyLimitMinutes &&
          bonusMinutes == other.bonusMinutes &&
          usedMinutes == other.usedMinutes &&
          iconName == other.iconName &&
          colorHex == other.colorHex;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      Object.hashAll(packageNames) ^
      dailyLimitMinutes.hashCode ^
      bonusMinutes.hashCode ^
      usedMinutes.hashCode ^
      (iconName?.hashCode ?? 0) ^
      (colorHex?.hashCode ?? 0);

  @override
  String toString() =>
      'AppCategoryRule(id: $id, name: $name, limit: $dailyLimitMinutes, used: $usedMinutes, bonus: $bonusMinutes, apps: ${packageNames.length})';
}

@immutable
class AppLimitsState {
  final List<String> blacklistedPackages;
  final List<AppCategoryRule> categories;
  final List<InstalledAppInfo> installedApps;
  final Map<String, int> appUsages;
  final DateTime? lastUpdated;

  const AppLimitsState({
    this.blacklistedPackages = const [],
    this.categories = const [],
    this.installedApps = const [],
    this.appUsages = const {},
    this.lastUpdated,
  });

  bool isBlacklisted(String packageName) =>
      blacklistedPackages.contains(packageName);

  AppCategoryRule? getCategoryForPackage(String packageName) {
    for (final cat in categories) {
      if (cat.packageNames.contains(packageName)) {
        return cat;
      }
    }
    return null;
  }

  InstalledAppInfo? getAppInfo(String packageName) {
    for (final app in installedApps) {
      if (app.packageName == packageName) {
        return app;
      }
    }
    return null;
  }

  String getAppName(String packageName) {
    final info = getAppInfo(packageName);
    if (info != null && info.appName.isNotEmpty) {
      return info.appName;
    }
    if (packageName.contains('.')) {
      final parts = packageName.split('.');
      final last = parts.last;
      if (last.isNotEmpty) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }
    return packageName;
  }

  Map<String, dynamic> toJson() => {
        'blacklistedPackages': blacklistedPackages,
        'categories': categories.map((c) => c.toJson()).toList(),
        'installedApps': installedApps.map((a) => a.toJson()).toList(),
        'appUsages': appUsages,
        if (lastUpdated != null) 'lastUpdated': lastUpdated!.toIso8601String(),
      };

  factory AppLimitsState.fromJson(Map<String, dynamic> json) {
    final blacklisted = (json['blacklistedPackages'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final categoriesList = (json['categories'] as List<dynamic>?)
            ?.map((e) =>
                AppCategoryRule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const [];

    final installedList = (json['installedApps'] as List<dynamic>?)
            ?.map((e) =>
                InstalledAppInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const [];

    final usages = (json['appUsages'] as Map<dynamic, dynamic>?)?.map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ) ??
        const {};

    DateTime? updated;
    if (json['lastUpdated'] != null) {
      if (json['lastUpdated'] is int) {
        updated =
            DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'] as int);
      } else {
        updated = DateTime.tryParse(json['lastUpdated'].toString());
      }
    }

    return AppLimitsState(
      blacklistedPackages: blacklisted,
      categories: categoriesList,
      installedApps: installedList,
      appUsages: usages,
      lastUpdated: updated,
    );
  }

  AppLimitsState copyWith({
    List<String>? blacklistedPackages,
    List<AppCategoryRule>? categories,
    List<InstalledAppInfo>? installedApps,
    Map<String, int>? appUsages,
    DateTime? lastUpdated,
  }) {
    return AppLimitsState(
      blacklistedPackages: blacklistedPackages ?? this.blacklistedPackages,
      categories: categories ?? this.categories,
      installedApps: installedApps ?? this.installedApps,
      appUsages: appUsages ?? this.appUsages,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLimitsState &&
          runtimeType == other.runtimeType &&
          listEquals(blacklistedPackages, other.blacklistedPackages) &&
          listEquals(categories, other.categories) &&
          listEquals(installedApps, other.installedApps) &&
          mapEquals(appUsages, other.appUsages);

  @override
  int get hashCode =>
      Object.hashAll(blacklistedPackages) ^
      Object.hashAll(categories) ^
      Object.hashAll(installedApps) ^
      Object.hashAll(appUsages.entries);
}
