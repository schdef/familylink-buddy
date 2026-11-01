import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pairing/pairing_repository.dart';
import 'bedtime_repository.dart';
import 'bedtime_schedule.dart';

class BedtimeScheduleScreen extends StatefulWidget {
  final PairedDevice device;
  final String? localIpAddress;

  const BedtimeScheduleScreen({
    super.key,
    required this.device,
    this.localIpAddress,
  });

  @override
  State<BedtimeScheduleScreen> createState() => _BedtimeScheduleScreenState();
}

class _BedtimeScheduleScreenState extends State<BedtimeScheduleScreen> {
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final repo = Provider.of<BedtimeRepository>(context, listen: false);
        repo.subscribeToDevice(widget.device.fcmToken);
      }
    });
  }

  Future<void> _updateSchedule(BedtimeSchedule newSchedule) async {
    setState(() => _isSaving = true);
    final repo = Provider.of<BedtimeRepository>(context, listen: false);
    final success = await repo.saveSchedule(
      widget.device.fcmToken,
      newSchedule,
      localIpAddress: widget.localIpAddress,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'WLAN-Zeitplan erfolgreich gespeichert' : 'Zeitplan konnte nicht gespeichert werden',
          ),
          backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleManualBlock(bool block) async {
    setState(() => _isSaving = true);
    final repo = Provider.of<BedtimeRepository>(context, listen: false);
    final success = await repo.toggleManualBlock(
      widget.device.fcmToken,
      block,
      localIpAddress: widget.localIpAddress,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            block ? 'WLAN wurde sofort gesperrt' : 'WLAN wurde wieder freigegeben',
          ),
          backgroundColor: block ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickTime({
    required BuildContext context,
    required bool isBedtime,
    required BedtimeSchedule schedule,
  }) async {
    final initialHour = isBedtime ? schedule.bedtimeHour : schedule.wakeupHour;
    final initialMinute = isBedtime ? schedule.bedtimeMinute : schedule.wakeupMinute;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      helpText: isBedtime ? 'Schlafenszeit festlegen' : 'Aufstehzeit festlegen',
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: const Color(0xFF1E293B),
              hourMinuteColor: const Color(0xFF0F172A),
              hourMinuteTextColor: Colors.white,
              dialBackgroundColor: const Color(0xFF0F172A),
              dialHandColor: const Color(0xFF6366F1),
              dialTextColor: Colors.white,
              entryModeIconColor: const Color(0xFF94A3B8),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final updated = isBedtime
          ? schedule.copyWith(bedtimeHour: picked.hour, bedtimeMinute: picked.minute)
          : schedule.copyWith(wakeupHour: picked.hour, wakeupMinute: picked.minute);
      await _updateSchedule(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'WLAN-Nachtruhe',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Consumer<BedtimeRepository>(
        builder: (context, repo, child) {
          final schedule = repo.schedule;
          final isBlocked = schedule.isCurrentlyBlocked;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Status Card
                _buildLiveStatusCard(isBlocked),
                const SizedBox(height: 20),

                // Manual Override Button
                _buildManualOverrideButton(isBlocked),
                const SizedBox(height: 24),

                // Master Schedule Switch Card
                _buildMasterSwitchCard(schedule),
                const SizedBox(height: 16),

                // Time Pickers Card
                _buildTimePickersCard(schedule),
                const SizedBox(height: 16),

                // Weekday Selector Card
                _buildWeekdaySelectorCard(schedule),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveStatusCard(bool isBlocked) {
    final color = isBlocked ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final icon = isBlocked ? Icons.wifi_off_rounded : Icons.wifi_rounded;
    final statusText = isBlocked ? 'WLAN ist gesperrt' : 'WLAN ist aktiv';
    final descText = isBlocked
        ? 'Die WLAN-Verbindung des Kindergeräts ist derzeit blockiert.'
        : 'Das Kind hat uneingeschränkten Zugriff auf das WLAN-Netzwerk.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  descText,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualOverrideButton(bool isBlocked) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : () => _toggleManualBlock(!isBlocked),
        icon: Icon(
          isBlocked ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: Colors.white,
          size: 22,
        ),
        label: Text(
          isBlocked ? 'WLAN jetzt einschalten' : 'WLAN jetzt ausschalten',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isBlocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildMasterSwitchCard(BedtimeSchedule schedule) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.bedtime_outlined,
              color: Color(0xFF6366F1),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WLAN-Nachtruhe automatisch steuern',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'WLAN zu festgelegten Uhrzeiten kappen',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: schedule.isEnabled,
            activeColor: const Color(0xFF6366F1),
            onChanged: (val) {
              _updateSchedule(schedule.copyWith(isEnabled: val));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickersCard(BedtimeSchedule schedule) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uhrzeiten',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildTimeTile(
                  title: 'Schlafenszeit (WLAN Aus)',
                  time: schedule.bedtimeFormattedWithUnit,
                  icon: Icons.nightlight_round,
                  color: const Color(0xFFEF4444),
                  onTap: () => _pickTime(
                    context: context,
                    isBedtime: true,
                    schedule: schedule,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimeTile(
                  title: 'Aufstehzeit (WLAN An)',
                  time: schedule.wakeupFormattedWithUnit,
                  icon: Icons.wb_sunny_rounded,
                  color: const Color(0xFF10B981),
                  onTap: () => _pickTime(
                    context: context,
                    isBedtime: false,
                    schedule: schedule,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeTile({
    required String title,
    required String time,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekdaySelectorCard(BedtimeSchedule schedule) {
    const dayMap = {
      1: 'Mo',
      2: 'Di',
      3: 'Mi',
      4: 'Do',
      5: 'Fr',
      6: 'Sa',
      7: 'So',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aktive Wochentage',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                schedule.activeDaysSummary,
                style: const TextStyle(
                  color: Color(0xFF6366F1),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Quick Preset Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // School days: Sunday through Thursday evening
                    _updateSchedule(schedule.copyWith(activeDays: [7, 1, 2, 3, 4]));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Schultage (So–Do)', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _updateSchedule(schedule.copyWith(activeDays: [1, 2, 3, 4, 5, 6, 7]));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Jeden Tag', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekday selector chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: dayMap.entries.map((entry) {
              final dayIndex = entry.key;
              final dayName = entry.value;
              final isSelected = schedule.isDayActive(dayIndex);

              return GestureDetector(
                onTap: () {
                  final List<int> updatedDays = List.from(schedule.activeDays);
                  if (isSelected) {
                    updatedDays.remove(dayIndex);
                  } else {
                    updatedDays.add(dayIndex);
                    updatedDays.sort();
                  }
                  _updateSchedule(schedule.copyWith(activeDays: updatedDays));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF334155),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    dayName,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
