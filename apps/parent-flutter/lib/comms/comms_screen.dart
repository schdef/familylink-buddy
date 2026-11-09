import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import 'comms_repository.dart';
import '../l10n/app_strings.dart';

class CommsScreen extends StatefulWidget {
  final PairedDevice device;

  const CommsScreen({
    super.key,
    required this.device,
  });

  @override
  State<CommsScreen> createState() => _CommsScreenState();
}

class _CommsScreenState extends State<CommsScreen> with SingleTickerProviderStateMixin {
  late CommsRepository _commsRepository;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _commsRepository = CommsRepository();
    _commsRepository.listenToChildSpeaking(widget.device.fcmToken);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _commsRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEmulator = const String.fromEnvironment('USE_EMULATOR') == 'true' ||
        widget.device.fcmToken == 'emulator' ||
        widget.device.fcmToken.isEmpty;

    return ChangeNotifierProvider.value(
      value: _commsRepository,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: Text(context.strings.walkieTalkieTitle),
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
        ),
        body: Consumer<CommsRepository>(
          builder: (context, repo, child) {
            final isTalking = repo.isStreaming;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (repo.missedCallNotification != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Color(0xFFEF4444)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.strings.missedCallTitle,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  repo.missedCallNotification!,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => repo.clearMissedNotification(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Active Connection Header Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.speaker_phone, color: Color(0xFF6366F1), size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.device.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isEmulator ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isEmulator ? context.strings.channelSimulatedActive : context.strings.channelReady,
                                    style: TextStyle(
                                      color: isEmulator ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Push-to-Talk button layout
                  Center(
                    child: GestureDetector(
                      onTapDown: (_) async {
                        debugPrint('Walkie-talkie button pressed (onTapDown)');
                        await repo.startWalkieTalkieSession(
                          childToken: widget.device.fcmToken,
                          localSdpOffer: 'mock_sdp_offer',
                          isEmulator: isEmulator,
                        );
                      },
                      onTapUp: (_) async {
                        debugPrint('Walkie-talkie button released (onTapUp)');
                        await repo.closeSession(
                          childToken: widget.device.fcmToken,
                          isEmulator: isEmulator,
                        );
                      },
                      onTapCancel: () async {
                        debugPrint('Walkie-talkie button touch cancelled (onTapCancel)');
                        await repo.closeSession(
                          childToken: widget.device.fcmToken,
                          isEmulator: isEmulator,
                        );
                      },
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          final double currentScale = isTalking ? _pulseAnimation.value : 1.0;
                          return Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: isTalking
                                      ? const Color(0xFFEF4444).withOpacity(0.4)
                                      : const Color(0xFF6366F1).withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: isTalking ? 8 : 4,
                                ),
                              ],
                            ),
                            child: Transform.scale(
                              scale: currentScale,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: isTalking
                                        ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                                        : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(color: Colors.white.withOpacity(0.2), width: 3),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isTalking ? Icons.mic : Icons.mic_none,
                                      color: Colors.white,
                                      size: 56,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isTalking ? context.strings.talking : context.strings.holdToTalk,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Waveform custom simulator display
                  if (isTalking) ...[
                    Center(
                      child: Text(
                        context.strings.audioStreaming,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Settings Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.strings.walkieTalkieRules,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            context.strings.autoPlayVoiceTitle,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            context.strings.autoPlayVoiceSubtitle,
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                          value: repo.autoPlayVoice,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (val) {
                            repo.updateSettings(
                              childToken: widget.device.fcmToken,
                              childCanInitiateVal: repo.childCanInitiate,
                              autoPlayVoiceVal: val,
                            );
                          },
                        ),
                        const Divider(color: Color(0xFF334155), height: 32),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            context.strings.childCanInitiateTitle,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            context.strings.childCanInitiateSubtitle,
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                          value: repo.childCanInitiate,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (val) {
                            repo.updateSettings(
                              childToken: widget.device.fcmToken,
                              childCanInitiateVal: val,
                              autoPlayVoiceVal: repo.autoPlayVoice,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
