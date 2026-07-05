import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/comms/comms_repository.dart';

void main() {
  group('CommsSession and CommsRepository Unit Tests', () {
    test('CommsSession constructor and property mapping', () {
      final now = DateTime.now();
      final session = CommsSession(
        sessionId: 'comms_test_123',
        status: 'active',
        type: 'voice',
        timestamp: now,
      );

      expect(session.sessionId, 'comms_test_123');
      expect(session.status, 'active');
      expect(session.type, 'voice');
      expect(session.timestamp, now);
    });

    test('CommsRepository default configurations', () {
      final repo = CommsRepository();

      expect(repo.isConnecting, false);
      expect(repo.isStreaming, false);
      expect(repo.activeSessionId, null);
      expect(repo.childCanInitiate, true);
      expect(repo.autoPlayVoice, true);
    });

    test('CommsRepository local settings updating behavior', () {
      final repo = CommsRepository();
      
      // Simulate direct update (settings bypass firebase for local fast check)
      repo.updateSettings(
        childToken: 'emulator',
        childCanInitiateVal: false,
        autoPlayVoiceVal: false,
      );

      expect(repo.childCanInitiate, false);
      expect(repo.autoPlayVoice, false);
    });
  });
}
