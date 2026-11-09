class ScreenshotItem {
  final String id;
  final DateTime timestamp;
  final String base64Image;
  final String? deviceModel;
  final String? foregroundApp;
  final String? foregroundPackage;
  final String captureType;
  final String? facing;
  final bool flash;

  const ScreenshotItem({
    required this.id,
    required this.timestamp,
    required this.base64Image,
    this.deviceModel,
    this.foregroundApp,
    this.foregroundPackage,
    this.captureType = 'screenshot',
    this.facing,
    this.flash = false,
  });

  bool get isCamera => captureType == 'camera';

  factory ScreenshotItem.fromJson(Map<String, dynamic> json, {String? id}) {
    DateTime ts;
    final rawTs = json['timestamp'];
    if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    return ScreenshotItem(
      id: id ?? (json['id'] as String? ?? ''),
      timestamp: ts,
      base64Image: (json['base64Image'] ?? json['image'] ?? json['screenshot'] ?? '') as String,
      deviceModel: json['deviceModel'] as String?,
      foregroundApp: json['foregroundApp'] as String?,
      foregroundPackage: json['foregroundPackage'] as String?,
      captureType: (json['captureType'] as String?) ?? 'screenshot',
      facing: json['facing'] as String?,
      flash: json['flash'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'base64Image': base64Image,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (foregroundApp != null) 'foregroundApp': foregroundApp,
      if (foregroundPackage != null) 'foregroundPackage': foregroundPackage,
      'captureType': captureType,
      if (facing != null) 'facing': facing,
      'flash': flash,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'base64Image': base64Image,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (foregroundApp != null) 'foregroundApp': foregroundApp,
      if (foregroundPackage != null) 'foregroundPackage': foregroundPackage,
      'captureType': captureType,
      if (facing != null) 'facing': facing,
      'flash': flash,
    };
  }

  ScreenshotItem copyWith({
    String? id,
    DateTime? timestamp,
    String? base64Image,
    String? deviceModel,
    String? foregroundApp,
    String? foregroundPackage,
    String? captureType,
    String? facing,
    bool? flash,
  }) {
    return ScreenshotItem(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      base64Image: base64Image ?? this.base64Image,
      deviceModel: deviceModel ?? this.deviceModel,
      foregroundApp: foregroundApp ?? this.foregroundApp,
      foregroundPackage: foregroundPackage ?? this.foregroundPackage,
      captureType: captureType ?? this.captureType,
      facing: facing ?? this.facing,
      flash: flash ?? this.flash,
    );
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s Uhr';
  }

  String get formattedDate {
    final d = timestamp.day.toString().padLeft(2, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final y = timestamp.year;
    return '$d.$m.$y';
  }

  String get formattedDateTime => '$formattedDate $formattedTime';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenshotItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          timestamp == other.timestamp &&
          base64Image == other.base64Image &&
          deviceModel == other.deviceModel &&
          foregroundApp == other.foregroundApp &&
          foregroundPackage == other.foregroundPackage &&
          captureType == other.captureType &&
          facing == other.facing &&
          flash == other.flash;

  @override
  int get hashCode =>
      id.hashCode ^
      timestamp.hashCode ^
      base64Image.hashCode ^
      (deviceModel?.hashCode ?? 0) ^
      (foregroundApp?.hashCode ?? 0) ^
      (foregroundPackage?.hashCode ?? 0) ^
      captureType.hashCode ^
      (facing?.hashCode ?? 0) ^
      flash.hashCode;
}
