import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/time_bank/time_bank_repository.dart';

class FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic>? _data;

  FakeDocumentSnapshot(this.id, this._data);

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data?[field];

  @override
  dynamic operator [](Object field) => _data?[field];

  @override
  bool get exists => _data != null;

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();

  @override
  DocumentReference<Map<String, dynamic>> get reference => throw UnimplementedError();
}

void main() {
  group('Time Bank Models Tests', () {
    test('TransactionModel.fromFirestore parses correctly', () {
      final doc = FakeDocumentSnapshot('tx-123', {
        'timestamp': Timestamp.fromDate(DateTime(2026, 7, 5, 12, 0)),
        'type': 'EARN',
        'amount': 15,
        'description': '30 Min lesen',
        'emoji': '📚',
        'date': '2026-07-05',
      });

      final model = TransactionModel.fromFirestore(doc);
      expect(model.id, 'tx-123');
      expect(model.type, 'EARN');
      expect(model.amount, 15);
      expect(model.description, '30 Min lesen');
      expect(model.emoji, '📚');
      expect(model.date, '2026-07-05');
      expect(model.timestamp.year, 2026);
    });

    test('TaskModel.fromFirestore parses correctly', () {
      final doc = FakeDocumentSnapshot('task-456', {
        'title': 'Zimmer aufräumen',
        'emoji': '🧹',
        'reward': 10,
        'hasDuration': true,
        'durationMinutes': 15,
        'sortOrder': 2,
        'createdBy': 'parent',
      });

      final model = TaskModel.fromFirestore(doc);
      expect(model.id, 'task-456');
      expect(model.title, 'Zimmer aufräumen');
      expect(model.emoji, '🧹');
      expect(model.reward, 10);
      expect(model.hasDuration, true);
      expect(model.durationMinutes, 15);
      expect(model.sortOrder, 2);
      expect(model.createdBy, 'parent');
    });

    test('RewardModel.fromFirestore parses correctly', () {
      final doc = FakeDocumentSnapshot('reward-789', {
        'title': '1 Std. Minecraft',
        'emoji': '🎮',
        'cost': 50,
        'sortOrder': 0,
        'createdBy': 'parent',
      });

      final model = RewardModel.fromFirestore(doc);
      expect(model.id, 'reward-789');
      expect(model.title, '1 Std. Minecraft');
      expect(model.emoji, '🎮');
      expect(model.cost, 50);
      expect(model.sortOrder, 0);
      expect(model.createdBy, 'parent');
    });

    test('ClaimModel.fromFirestore parses correctly', () {
      final doc = FakeDocumentSnapshot('claim-999', {
        'rewardId': 'reward-789',
        'title': '1 Std. Minecraft',
        'emoji': '🎮',
        'cost': 50,
        'status': 'PENDING',
        'claimedAt': Timestamp.fromDate(DateTime(2026, 7, 5, 12, 10)),
        'fulfilledAt': null,
      });

      final model = ClaimModel.fromFirestore(doc);
      expect(model.id, 'claim-999');
      expect(model.rewardId, 'reward-789');
      expect(model.title, '1 Std. Minecraft');
      expect(model.emoji, '🎮');
      expect(model.cost, 50);
      expect(model.status, 'PENDING');
      expect(model.claimedAt.minute, 10);
      expect(model.fulfilledAt, isNull);
    });
  });
}
