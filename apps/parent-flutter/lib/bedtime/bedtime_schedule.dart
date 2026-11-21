import 'package:flutter/foundation.dart';
import 'package:parent_app/l10n/app_strings.dart';

@immutable
class BedtimeSchedule {
  final bool isEnabled;
  final int bedtimeHour;
  final int bedtimeMinute;
  final int wakeupHour;
  final int wakeupMinute;
  final List<int> activeDays;
  final bool isCurrentlyBlocked;

  const BedtimeSchedule({
    this.isEnabled = false,
    this.bedtimeHour = 20,
    this.bedtimeMinute = 30,
    this.wakeupHour = 6,
    this.wakeupMinute = 45,
    this.activeDays = const [1, 2, 3, 4, 5, 6, 7],
    this.isCurrentlyBlocked = false,
  });

  /// Formatted bedtime representation, e.g. "20:30"
  String get bedtimeFormatted =>
      '${bedtimeHour.toString().padLeft(2, '0')}:${bedtimeMinute.toString().padLeft(2, '0')}';

  /// Formatted wakeup representation, e.g. "06:45"
  String get wakeupFormatted =>
      '${wakeupHour.toString().padLeft(2, '0')}:${wakeupMinute.toString().padLeft(2, '0')}';

  /// Formatted with German time suffix, e.g. "20:30 Uhr"
  String get bedtimeFormattedWithUnit => '$bedtimeFormatted Uhr';

  /// Formatted with German time suffix, e.g. "06:45 Uhr"
  String get wakeupFormattedWithUnit => '$wakeupFormatted Uhr';

  /// Check whether a given ISO weekday (1 = Mon ... 7 = Sun) is active
  bool isDayActive(int weekday) => activeDays.contains(weekday);

  /// Quick summary of active days localized with provided [AppStrings]
  String localizedActiveDaysSummary(AppStrings strings) => strings.formatDaysSummary(activeDays);

  /// Quick summary of active days
  String get activeDaysSummary => localizedActiveDaysSummary(AppStrings.current);

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': isEnabled,
      'bedtimeHour': bedtimeHour,
      'bedtimeMinute': bedtimeMinute,
      'wakeupHour': wakeupHour,
      'wakeupMinute': wakeupMinute,
      'activeDays': activeDays,
      'isCurrentlyBlocked': isCurrentlyBlocked,
    };
  }

  factory BedtimeSchedule.fromJson(Map<String, dynamic> json) {
    final rawDays = json['activeDays'] as List<dynamic>?;
    final List<int> days = rawDays != null
        ? rawDays.map((e) => (e as num).toInt()).toList()
        : const [1, 2, 3, 4, 5, 6, 7];

    return BedtimeSchedule(
      isEnabled: json['isEnabled'] as bool? ?? false,
      bedtimeHour: (json['bedtimeHour'] as num?)?.toInt() ?? 20,
      bedtimeMinute: (json['bedtimeMinute'] as num?)?.toInt() ?? 30,
      wakeupHour: (json['wakeupHour'] as num?)?.toInt() ?? 6,
      wakeupMinute: (json['wakeupMinute'] as num?)?.toInt() ?? 45,
      activeDays: days,
      isCurrentlyBlocked: json['isCurrentlyBlocked'] as bool? ?? false,
    );
  }

  BedtimeSchedule copyWith({
    bool? isEnabled,
    int? bedtimeHour,
    int? bedtimeMinute,
    int? wakeupHour,
    int? wakeupMinute,
    List<int>? activeDays,
    bool? isCurrentlyBlocked,
  }) {
    return BedtimeSchedule(
      isEnabled: isEnabled ?? this.isEnabled,
      bedtimeHour: bedtimeHour ?? this.bedtimeHour,
      bedtimeMinute: bedtimeMinute ?? this.bedtimeMinute,
      wakeupHour: wakeupHour ?? this.wakeupHour,
      wakeupMinute: wakeupMinute ?? this.wakeupMinute,
      activeDays: activeDays != null ? List<int>.from(activeDays) : this.activeDays,
      isCurrentlyBlocked: isCurrentlyBlocked ?? this.isCurrentlyBlocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BedtimeSchedule &&
          runtimeType == other.runtimeType &&
          isEnabled == other.isEnabled &&
          bedtimeHour == other.bedtimeHour &&
          bedtimeMinute == other.bedtimeMinute &&
          wakeupHour == other.wakeupHour &&
          wakeupMinute == other.wakeupMinute &&
          listEquals(activeDays, other.activeDays) &&
          isCurrentlyBlocked == other.isCurrentlyBlocked;

  @override
  int get hashCode =>
      isEnabled.hashCode ^
      bedtimeHour.hashCode ^
      bedtimeMinute.hashCode ^
      wakeupHour.hashCode ^
      wakeupMinute.hashCode ^
      Object.hashAll(activeDays) ^
      isCurrentlyBlocked.hashCode;

  @override
  String toString() {
    return 'BedtimeSchedule(enabled: $isEnabled, bedtime: $bedtimeFormatted, wakeup: $wakeupFormatted, days: $activeDays, blocked: $isCurrentlyBlocked)';
  }
}
