import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/volume/volume_repository.dart';

void main() {
  group('VolumeState Tests', () {
    test('Default values', () {
      const state = VolumeState();
      expect(state.mediaVolume, -1);
      expect(state.ringtoneVolume, -1);
      expect(state.alarmVolume, -1);
      expect(state.maxMediaVolume, 15);
      expect(state.maxRingtoneVolume, 15);
      expect(state.maxAlarmVolume, 15);
      expect(state.isMuted, false);
      expect(state.timestamp, null);
      expect(state.isKnown, false);
    });

    test('fromJson parsing', () {
      final json = {
        'mediaVolume': 5,
        'ringtoneVolume': 7,
        'alarmVolume': 10,
        'maxMediaVolume': 15,
        'maxRingtoneVolume': 15,
        'maxAlarmVolume': 15,
        'isMuted': false,
        'timestamp': 1680000000000,
      };

      final state = VolumeState.fromJson(json);
      expect(state.mediaVolume, 5);
      expect(state.ringtoneVolume, 7);
      expect(state.alarmVolume, 10);
      expect(state.isMuted, false);
      expect(state.timestamp, DateTime.fromMillisecondsSinceEpoch(1680000000000));
      expect(state.isKnown, true);
    });

    test('fromJson parsing with nulls / missing values', () {
      final json = <String, dynamic>{};
      final state = VolumeState.fromJson(json);
      expect(state.mediaVolume, -1);
      expect(state.maxMediaVolume, 15);
      expect(state.isMuted, false);
      expect(state.timestamp, null);
    });
  });
}
