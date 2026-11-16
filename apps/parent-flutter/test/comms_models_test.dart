import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/comms/comms_models.dart';

void main() {
  group('CallType Enum Tests', () {
    test('fromString parses correctly and handles fallback', () {
      expect(CallType.fromString('INCOMING'), CallType.incoming);
      expect(CallType.fromString('incoming'), CallType.incoming);
      expect(CallType.fromString('OUTGOING'), CallType.outgoing);
      expect(CallType.fromString('outgoing'), CallType.outgoing);
      expect(CallType.fromString('MISSED'), CallType.missed);
      expect(CallType.fromString('missed'), CallType.missed);
      expect(CallType.fromString('REJECTED'), CallType.rejected);
      expect(CallType.fromString('rejected'), CallType.rejected);
      expect(CallType.fromString(null), CallType.incoming);
      expect(CallType.fromString('UNKNOWN_TYPE'), CallType.incoming);
    });

    test('toUppercaseString formats uppercase strings', () {
      expect(CallType.incoming.toUppercaseString(), 'INCOMING');
      expect(CallType.outgoing.toUppercaseString(), 'OUTGOING');
      expect(CallType.missed.toUppercaseString(), 'MISSED');
      expect(CallType.rejected.toUppercaseString(), 'REJECTED');
    });
  });

  group('CallRecord Model Tests', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'id': 'call_101',
        'phoneNumber': '+491701234567',
        'contactName': 'Grandma',
        'callType': 'INCOMING',
        'timestamp': 1731664800000,
        'durationSeconds': 145,
      };

      final record = CallRecord.fromJson(json);

      expect(record.id, 'call_101');
      expect(record.phoneNumber, '+491701234567');
      expect(record.contactName, 'Grandma');
      expect(record.callType, CallType.incoming);
      expect(record.timestamp, 1731664800000);
      expect(record.durationSeconds, 145);
      expect(record.displayName, 'Grandma');
      expect(record.dateTime.millisecondsSinceEpoch, 1731664800000);

      final outJson = record.toJson();
      expect(outJson['id'], 'call_101');
      expect(outJson['phoneNumber'], '+491701234567');
      expect(outJson['contactName'], 'Grandma');
      expect(outJson['callType'], 'INCOMING');
      expect(outJson['timestamp'], 1731664800000);
      expect(outJson['durationSeconds'], 145);
    });

    test('fromJson handles legacy fallback fields', () {
      final json = {
        'id': 'call_102',
        'number': '+15559876543',
        'name': null,
        'type': 'MISSED',
        'timestamp': '1731664900000',
        'duration': '0',
      };

      final record = CallRecord.fromJson(json);
      expect(record.id, 'call_102');
      expect(record.phoneNumber, '+15559876543');
      expect(record.contactName, isNull);
      expect(record.displayName, '+15559876543');
      expect(record.callType, CallType.missed);
      expect(record.timestamp, 1731664900000);
      expect(record.durationSeconds, 0);
    });

    test('copyWith and equality', () {
      const record1 = CallRecord(
        id: 'c1',
        phoneNumber: '123',
        contactName: 'Dad',
        callType: CallType.outgoing,
        timestamp: 1000,
        durationSeconds: 30,
      );

      final record2 = record1.copyWith(durationSeconds: 45);
      expect(record2.durationSeconds, 45);
      expect(record2.phoneNumber, '123');
      expect(record1 == record2, isFalse);

      final record3 = record1.copyWith();
      expect(record1 == record3, isTrue);
      expect(record1.hashCode, record3.hashCode);
    });
  });

  group('ChatMessageRecord Model Tests', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'id': 'msg_201',
        'appPackage': 'com.whatsapp',
        'appName': 'WhatsApp',
        'senderOrChat': 'Mom',
        'text': 'Dinner is ready in 15 minutes!',
        'isOutgoing': false,
        'timestamp': 1731665000000,
      };

      final record = ChatMessageRecord.fromJson(json);

      expect(record.id, 'msg_201');
      expect(record.appPackage, 'com.whatsapp');
      expect(record.appName, 'WhatsApp');
      expect(record.senderOrChat, 'Mom');
      expect(record.text, 'Dinner is ready in 15 minutes!');
      expect(record.isOutgoing, isFalse);
      expect(record.timestamp, 1731665000000);
      expect(record.dateTime.millisecondsSinceEpoch, 1731665000000);

      final outJson = record.toJson();
      expect(outJson['id'], 'msg_201');
      expect(outJson['appPackage'], 'com.whatsapp');
      expect(outJson['appName'], 'WhatsApp');
      expect(outJson['senderOrChat'], 'Mom');
      expect(outJson['text'], 'Dinner is ready in 15 minutes!');
      expect(outJson['isOutgoing'], isFalse);
      expect(outJson['timestamp'], 1731665000000);
    });

    test('fromJson handles string booleans and fallback aliases', () {
      final json = {
        'id': 'msg_202',
        'package': 'org.telegram.messenger',
        'appName': 'Telegram',
        'chat': 'Homework Group',
        'message': 'Page 42 exercise 3',
        'outgoing': 'true',
        'timestamp': 1731665100000,
      };

      final record = ChatMessageRecord.fromJson(json);
      expect(record.id, 'msg_202');
      expect(record.appPackage, 'org.telegram.messenger');
      expect(record.senderOrChat, 'Homework Group');
      expect(record.text, 'Page 42 exercise 3');
      expect(record.isOutgoing, isTrue);
    });

    test('copyWith and equality', () {
      const msg1 = ChatMessageRecord(
        id: 'm1',
        appPackage: 'com.whatsapp',
        appName: 'WhatsApp',
        senderOrChat: 'Alice',
        text: 'Hello',
        isOutgoing: false,
        timestamp: 5000,
      );

      final msg2 = msg1.copyWith(text: 'Hello World');
      expect(msg2.text, 'Hello World');
      expect(msg1 == msg2, isFalse);

      final msg3 = msg1.copyWith();
      expect(msg1 == msg3, isTrue);
      expect(msg1.hashCode, msg3.hashCode);
    });
  });
}
