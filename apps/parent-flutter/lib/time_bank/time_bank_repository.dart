import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;
  final DateTime timestamp;
  final String type;
  final int amount;
  final String description;
  final String emoji;
  final String date;

  TransactionModel({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.amount,
    required this.description,
    required this.emoji,
    required this.date,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final timestampVal = data['timestamp'] as Timestamp?;
    return TransactionModel(
      id: doc.id,
      timestamp: timestampVal?.toDate() ?? DateTime.now(),
      type: data['type'] as String? ?? 'MANUAL_AWARD',
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      description: data['description'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '⏳',
      date: data['date'] as String? ?? '',
    );
  }
}

class TaskModel {
  final String id;
  final String title;
  final String emoji;
  final int reward;
  final bool hasDuration;
  final int durationMinutes;
  final int sortOrder;
  final String createdBy;

  TaskModel({
    required this.id,
    required this.title,
    required this.emoji,
    required this.reward,
    required this.hasDuration,
    required this.durationMinutes,
    required this.sortOrder,
    required this.createdBy,
  });

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '📋',
      reward: (data['reward'] as num?)?.toInt() ?? 0,
      hasDuration: data['hasDuration'] as bool? ?? false,
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}

class RewardModel {
  final String id;
  final String title;
  final String emoji;
  final int cost;
  final int sortOrder;
  final String createdBy;

  RewardModel({
    required this.id,
    required this.title,
    required this.emoji,
    required this.cost,
    required this.sortOrder,
    required this.createdBy,
  });

  factory RewardModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RewardModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '🎁',
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}

class ClaimModel {
  final String id;
  final String rewardId;
  final String title;
  final String emoji;
  final int cost;
  final String status;
  final DateTime claimedAt;
  final DateTime? fulfilledAt;

  ClaimModel({
    required this.id,
    required this.rewardId,
    required this.title,
    required this.emoji,
    required this.cost,
    required this.status,
    required this.claimedAt,
    this.fulfilledAt,
  });

  factory ClaimModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final claimedAtVal = data['claimedAt'] as Timestamp?;
    final fulfilledAtVal = data['fulfilledAt'] as Timestamp?;
    return ClaimModel(
      id: doc.id,
      rewardId: data['rewardId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '🎁',
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? 'PENDING',
      claimedAt: claimedAtVal?.toDate() ?? DateTime.now(),
      fulfilledAt: fulfilledAtVal?.toDate(),
    );
  }
}

class TimeBankRepository extends ChangeNotifier {
  int _balance = 0;
  bool _isEnabled = false;
  bool _isChildVisible = false;
  List<TransactionModel> _transactions = [];
  List<TaskModel> _tasks = [];
  List<RewardModel> _rewards = [];
  List<ClaimModel> _claims = [];

  int get balance => _balance;
  bool get isEnabled => _isEnabled;
  bool get isChildVisible => _isChildVisible;
  List<TransactionModel> get transactions => _transactions;
  List<TaskModel> get tasks => _tasks;
  List<RewardModel> get rewards => _rewards;
  List<ClaimModel> get claims => _claims;

  final Map<String, StreamSubscription> _subscriptions = {};

  void subscribeToDevice(String childToken) {
    unsubscribe();
    if (childToken.isEmpty) return;

    final docRef = FirebaseFirestore.instance.collection('pairings').doc(childToken);

    // 1. Subscribe to pairing metadata
    _subscriptions['metadata'] = docRef.snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          _balance = (data['timeBankBalance'] as num?)?.toInt() ?? 0;
          _isEnabled = data['timeBankEnabled'] as bool? ?? false;
          _isChildVisible = data['timeBankChildVisible'] as bool? ?? false;
          notifyListeners();
        }
      }
    });

    // 2. Subscribe to transactions
    _subscriptions['transactions'] = docRef
        .collection('time_bank_transactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      _transactions = snapshot.docs.map((doc) => TransactionModel.fromFirestore(doc)).toList();
      notifyListeners();
    });

    // 3. Subscribe to tasks
    _subscriptions['tasks'] = docRef
        .collection('time_bank_tasks')
        .orderBy('sortOrder')
        .snapshots()
        .listen((snapshot) {
      _tasks = snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
      notifyListeners();
    });

    // 4. Subscribe to rewards
    _subscriptions['rewards'] = docRef
        .collection('time_bank_rewards')
        .orderBy('sortOrder')
        .snapshots()
        .listen((snapshot) {
      _rewards = snapshot.docs.map((doc) => RewardModel.fromFirestore(doc)).toList();
      notifyListeners();
    });

    // 5. Subscribe to claims
    _subscriptions['claims'] = docRef
        .collection('time_bank_claims')
        .orderBy('claimedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _claims = snapshot.docs.map((doc) => ClaimModel.fromFirestore(doc)).toList();
      notifyListeners();
    });
  }

  void unsubscribe() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _balance = 0;
    _isEnabled = false;
    _isChildVisible = false;
    _transactions.clear();
    _tasks.clear();
    _rewards.clear();
    _claims.clear();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }

  Future<void> awardCoins(String childToken, int amount, String description, String emoji) async {
    if (childToken.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('pairings').doc(childToken);
    final txRef = docRef.collection('time_bank_transactions').doc();
    
    final batch = FirebaseFirestore.instance.batch();
    batch.update(docRef, {
      'timeBankBalance': FieldValue.increment(amount),
      'coinAward': {
        'amount': amount,
        'description': description,
        'emoji': emoji,
        'timestamp': FieldValue.serverTimestamp(),
      }
    });
    batch.set(txRef, {
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'MANUAL_AWARD',
      'amount': amount,
      'description': description,
      'emoji': emoji,
      'awardedBy': 'parent',
      'date': DateTime.now().toIso8601String().split('T')[0],
    });
    
    await batch.commit();
  }

  Future<void> createTask(String childToken, String title, String emoji, int reward, bool hasDuration, int durationMinutes) async {
    if (childToken.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('pairings').doc(childToken);
    final taskRef = docRef.collection('time_bank_tasks').doc();

    final sortOrder = _tasks.length;
    await taskRef.set({
      'title': title,
      'emoji': emoji,
      'reward': reward,
      'hasDuration': hasDuration,
      'durationMinutes': durationMinutes,
      'sortOrder': sortOrder,
      'createdBy': 'parent',
    });
  }

  Future<void> deleteTask(String childToken, String taskId) async {
    if (childToken.isEmpty || taskId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('pairings')
        .doc(childToken)
        .collection('time_bank_tasks')
        .doc(taskId)
        .delete();
  }

  Future<void> createReward(String childToken, String title, String emoji, int cost) async {
    if (childToken.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('pairings').doc(childToken);
    final rewardRef = docRef.collection('time_bank_rewards').doc();

    final sortOrder = _rewards.length;
    await rewardRef.set({
      'title': title,
      'emoji': emoji,
      'cost': cost,
      'sortOrder': sortOrder,
      'createdBy': 'parent',
    });
  }

  Future<void> deleteReward(String childToken, String rewardId) async {
    if (childToken.isEmpty || rewardId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('pairings')
        .doc(childToken)
        .collection('time_bank_rewards')
        .doc(rewardId)
        .delete();
  }

  Future<void> fulfillClaim(String childToken, String claimId) async {
    if (childToken.isEmpty || claimId.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    final claimDoc = FirebaseFirestore.instance
        .collection('pairings')
        .doc(childToken)
        .collection('time_bank_claims')
        .doc(claimId);
    final pairingDoc = FirebaseFirestore.instance
        .collection('pairings')
        .doc(childToken);

    batch.update(claimDoc, {
      'status': 'FULFILLED',
      'fulfilledAt': FieldValue.serverTimestamp(),
    });
    batch.update(pairingDoc, {
      'pendingClaimsCount': FieldValue.increment(-1),
    });
    
    await batch.commit();
  }

  Future<void> setTimeBankEnabled(String childToken, bool enabled) async {
    if (childToken.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('pairings')
        .doc(childToken)
        .update({
      'timeBankEnabled': enabled,
    });
  }

  Future<void> setChildVisible(String childToken, bool visible) async {
    if (childToken.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('pairings')
        .doc(childToken)
        .update({
      'timeBankChildVisible': visible,
    });
  }
}
