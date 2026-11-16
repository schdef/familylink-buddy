enum CallType {
  incoming,
  outgoing,
  missed,
  rejected;

  static CallType fromString(String? value) {
    if (value == null) return CallType.incoming;
    switch (value.toUpperCase().trim()) {
      case 'INCOMING':
        return CallType.incoming;
      case 'OUTGOING':
        return CallType.outgoing;
      case 'MISSED':
        return CallType.missed;
      case 'REJECTED':
        return CallType.rejected;
      default:
        return CallType.incoming;
    }
  }

  String toUppercaseString() {
    switch (this) {
      case CallType.incoming:
        return 'INCOMING';
      case CallType.outgoing:
        return 'OUTGOING';
      case CallType.missed:
        return 'MISSED';
      case CallType.rejected:
        return 'REJECTED';
    }
  }
}

class CallRecord {
  final String id;
  final String phoneNumber;
  final String? contactName;
  final CallType callType;
  final int timestamp;
  final int durationSeconds;

  const CallRecord({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    required this.callType,
    required this.timestamp,
    required this.durationSeconds,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  String get displayName =>
      (contactName != null && contactName!.trim().isNotEmpty)
          ? contactName!.trim()
          : phoneNumber;

  CallRecord copyWith({
    String? id,
    String? phoneNumber,
    String? contactName,
    CallType? callType,
    int? timestamp,
    int? durationSeconds,
  }) {
    return CallRecord(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      callType: callType ?? this.callType,
      timestamp: timestamp ?? this.timestamp,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    return CallRecord(
      id: json['id']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ??
          json['number']?.toString() ??
          '',
      contactName: json['contactName']?.toString() ?? json['name']?.toString(),
      callType: CallType.fromString(
        json['callType']?.toString() ?? json['type']?.toString(),
      ),
      timestamp: (json['timestamp'] is num)
          ? (json['timestamp'] as num).toInt()
          : (int.tryParse(json['timestamp']?.toString() ?? '') ?? 0),
      durationSeconds: (json['durationSeconds'] is num)
          ? (json['durationSeconds'] as num).toInt()
          : (json['duration'] is num)
              ? (json['duration'] as num).toInt()
              : (int.tryParse(json['durationSeconds']?.toString() ??
                      json['duration']?.toString() ??
                      '') ??
                  0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'contactName': contactName,
    'callType': callType.toUppercaseString(),
    'timestamp': timestamp,
    'durationSeconds': durationSeconds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          phoneNumber == other.phoneNumber &&
          contactName == other.contactName &&
          callType == other.callType &&
          timestamp == other.timestamp &&
          durationSeconds == other.durationSeconds;

  @override
  int get hashCode =>
      id.hashCode ^
      phoneNumber.hashCode ^
      (contactName?.hashCode ?? 0) ^
      callType.hashCode ^
      timestamp.hashCode ^
      durationSeconds.hashCode;

  @override
  String toString() =>
      'CallRecord(id: $id, phone: $phoneNumber, name: $contactName, type: $callType, timestamp: $timestamp, duration: ${durationSeconds}s)';
}

class ChatMessageRecord {
  final String id;
  final String appPackage;
  final String appName;
  final String senderOrChat;
  final String text;
  final bool isOutgoing;
  final int timestamp;

  const ChatMessageRecord({
    required this.id,
    required this.appPackage,
    required this.appName,
    required this.senderOrChat,
    required this.text,
    required this.isOutgoing,
    required this.timestamp,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  ChatMessageRecord copyWith({
    String? id,
    String? appPackage,
    String? appName,
    String? senderOrChat,
    String? text,
    bool? isOutgoing,
    int? timestamp,
  }) {
    return ChatMessageRecord(
      id: id ?? this.id,
      appPackage: appPackage ?? this.appPackage,
      appName: appName ?? this.appName,
      senderOrChat: senderOrChat ?? this.senderOrChat,
      text: text ?? this.text,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) {
    final rawOutgoing = json['isOutgoing'] ?? json['outgoing'];
    final bool isOutgoing = rawOutgoing == true ||
        rawOutgoing?.toString().toLowerCase() == 'true';

    return ChatMessageRecord(
      id: json['id']?.toString() ?? '',
      appPackage: json['appPackage']?.toString() ??
          json['package']?.toString() ??
          '',
      appName: json['appName']?.toString() ?? '',
      senderOrChat: json['senderOrChat']?.toString() ??
          json['sender']?.toString() ??
          json['chat']?.toString() ??
          '',
      text: json['text']?.toString() ??
          json['message']?.toString() ??
          json['body']?.toString() ??
          '',
      isOutgoing: isOutgoing,
      timestamp: (json['timestamp'] is num)
          ? (json['timestamp'] as num).toInt()
          : (int.tryParse(json['timestamp']?.toString() ?? '') ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'appPackage': appPackage,
    'appName': appName,
    'senderOrChat': senderOrChat,
    'text': text,
    'isOutgoing': isOutgoing,
    'timestamp': timestamp,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          appPackage == other.appPackage &&
          appName == other.appName &&
          senderOrChat == other.senderOrChat &&
          text == other.text &&
          isOutgoing == other.isOutgoing &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      id.hashCode ^
      appPackage.hashCode ^
      appName.hashCode ^
      senderOrChat.hashCode ^
      text.hashCode ^
      isOutgoing.hashCode ^
      timestamp.hashCode;

  @override
  String toString() =>
      'ChatMessageRecord(id: $id, app: $appName, package: $appPackage, sender: $senderOrChat, isOutgoing: $isOutgoing, timestamp: $timestamp, text: $text)';
}
