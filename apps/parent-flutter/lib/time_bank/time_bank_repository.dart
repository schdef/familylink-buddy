import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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

  factory TransactionModel.fromFirestore(dynamic doc) {
    final Map<String, dynamic> data = doc is Map<String, dynamic>
        ? doc
        : (doc.data() as Map<String, dynamic>? ?? {});
    final id = doc is Map ? (doc['id'] as String? ?? '') : doc.id as String;
    final timestampVal = data['timestamp'];
    DateTime ts;
    if (timestampVal is DateTime) {
      ts = timestampVal;
    } else if (timestampVal is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(timestampVal);
    } else if (timestampVal != null && timestampVal.toString().isNotEmpty) {
      try {
        // Handle custom timestamp mocks with toDate()
        ts = (timestampVal as dynamic).toDate();
      } catch (_) {
        ts = DateTime.tryParse(timestampVal.toString()) ?? DateTime.now();
      }
    } else {
      ts = DateTime.now();
    }

    return TransactionModel(
      id: id,
      timestamp: ts,
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

  factory TaskModel.fromFirestore(dynamic doc) {
    final Map<String, dynamic> data = doc is Map<String, dynamic>
        ? doc
        : (doc.data() as Map<String, dynamic>? ?? {});
    final id = doc is Map ? (doc['id'] as String? ?? '') : doc.id as String;
    return TaskModel(
      id: id,
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

  factory RewardModel.fromFirestore(dynamic doc) {
    final Map<String, dynamic> data = doc is Map<String, dynamic>
        ? doc
        : (doc.data() as Map<String, dynamic>? ?? {});
    final id = doc is Map ? (doc['id'] as String? ?? '') : doc.id as String;
    return RewardModel(
      id: id,
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

  factory ClaimModel.fromFirestore(dynamic doc) {
    final Map<String, dynamic> data = doc is Map<String, dynamic>
        ? doc
        : (doc.data() as Map<String, dynamic>? ?? {});
    final id = doc is Map ? (doc['id'] as String? ?? '') : doc.id as String;
    final claimedAtVal = data['claimedAt'];
    final fulfilledAtVal = data['fulfilledAt'];

    DateTime claimed;
    if (claimedAtVal is DateTime) {
      claimed = claimedAtVal;
    } else if (claimedAtVal is int) {
      claimed = DateTime.fromMillisecondsSinceEpoch(claimedAtVal);
    } else if (claimedAtVal != null) {
      try {
        claimed = (claimedAtVal as dynamic).toDate();
      } catch (_) {
        claimed = DateTime.tryParse(claimedAtVal.toString()) ?? DateTime.now();
      }
    } else {
      claimed = DateTime.now();
    }

    DateTime? fulfilled;
    if (fulfilledAtVal is DateTime) {
      fulfilled = fulfilledAtVal;
    } else if (fulfilledAtVal is int) {
      fulfilled = DateTime.fromMillisecondsSinceEpoch(fulfilledAtVal);
    } else if (fulfilledAtVal != null) {
      try {
        fulfilled = (fulfilledAtVal as dynamic).toDate();
      } catch (_) {
        fulfilled = DateTime.tryParse(fulfilledAtVal.toString());
      }
    }

    return ClaimModel(
      id: id,
      rewardId: data['rewardId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '🎁',
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? 'PENDING',
      claimedAt: claimed,
      fulfilledAt: fulfilled,
    );
  }
}

class TimeBankRepository extends ChangeNotifier {
  int _balance = 0;
  bool _isEnabled = true;
  bool _isChildVisible = true;
  final List<TransactionModel> _transactions = [];
  final List<TaskModel> _tasks = [];
  final List<RewardModel> _rewards = [];
  final List<ClaimModel> _claims = [];

  int get balance => _balance;
  bool get isEnabled => _isEnabled;
  bool get isChildVisible => _isChildVisible;
  List<TransactionModel> get transactions => List.unmodifiable(_transactions);
  List<TaskModel> get tasks => List.unmodifiable(_tasks);
  List<RewardModel> get rewards => List.unmodifiable(_rewards);
  List<ClaimModel> get claims => List.unmodifiable(_claims);

  void subscribeToDevice(String childToken) {
    // Local-First: State is maintained locally
  }

  void unsubscribe() {
    _balance = 0;
    _transactions.clear();
    _tasks.clear();
    _rewards.clear();
    _claims.clear();
  }

  Future<void> awardCoins(String childToken, int amount, String description, String emoji) async {
    _balance += amount;
    final now = DateTime.now();
    final tx = TransactionModel(
      id: const Uuid().v4(),
      timestamp: now,
      type: 'MANUAL_AWARD',
      amount: amount,
      description: description,
      emoji: emoji,
      date: now.toIso8601String().split('T')[0],
    );
    _transactions.insert(0, tx);
    notifyListeners();
  }

  Future<void> createTask(String childToken, String title, String emoji, int reward, bool hasDuration, int durationMinutes) async {
    final task = TaskModel(
      id: const Uuid().v4(),
      title: title,
      emoji: emoji,
      reward: reward,
      hasDuration: hasDuration,
      durationMinutes: durationMinutes,
      sortOrder: _tasks.length,
      createdBy: 'parent',
    );
    _tasks.add(task);
    notifyListeners();
  }

  Future<void> deleteTask(String childToken, String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  Future<void> createReward(String childToken, String title, String emoji, int cost) async {
    final reward = RewardModel(
      id: const Uuid().v4(),
      title: title,
      emoji: emoji,
      cost: cost,
      sortOrder: _rewards.length,
      createdBy: 'parent',
    );
    _rewards.add(reward);
    notifyListeners();
  }

  Future<void> deleteReward(String childToken, String rewardId) async {
    _rewards.removeWhere((r) => r.id == rewardId);
    notifyListeners();
  }

  Future<void> fulfillClaim(String childToken, String claimId) async {
    final idx = _claims.indexWhere((c) => c.id == claimId);
    if (idx >= 0) {
      final old = _claims[idx];
      _claims[idx] = ClaimModel(
        id: old.id,
        rewardId: old.rewardId,
        title: old.title,
        emoji: old.emoji,
        cost: old.cost,
        status: 'FULFILLED',
        claimedAt: old.claimedAt,
        fulfilledAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  Future<void> setTimeBankEnabled(String childToken, bool enabled) async {
    _isEnabled = enabled;
    notifyListeners();
  }

  Future<void> setChildVisible(String childToken, bool visible) async {
    _isChildVisible = visible;
    notifyListeners();
  }
}
