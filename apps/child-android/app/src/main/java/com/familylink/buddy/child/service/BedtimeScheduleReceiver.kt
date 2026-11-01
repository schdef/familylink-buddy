package com.familylink.buddy.child.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import com.familylink.buddy.child.data.BedtimeSchedule
import com.familylink.buddy.child.data.FamilyTimeRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Offline standalone receiver for scheduling and executing Bedtime Wi-Fi restrictions.
 */
class BedtimeScheduleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.d(TAG, "onReceive action=$action")

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "FamilyLinkBuddy:BedtimeScheduleLock"
        )?.apply {
            acquire(10_000L) // Max 10 seconds
        }

        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val repository = FamilyTimeRepository(context)
                val currentSchedule = repository.bedtimeSchedule.first()

                when (action) {
                    ACTION_TRIGGER_BEDTIME -> {
                        Log.i(TAG, "Bedtime triggered! Disabling Wi-Fi and updating repository.")
                        WifiAccessibilityHelperService.requestToggle(context, turnOn = false)
                        val updated = currentSchedule.copy(isCurrentlyBlocked = true)
                        repository.updateBedtimeSchedule(updated)
                        scheduleNextAlarms(context, updated)
                    }

                    ACTION_TRIGGER_WAKEUP -> {
                        Log.i(TAG, "Wakeup triggered! Restoring Wi-Fi and updating repository.")
                        WifiAccessibilityHelperService.requestToggle(context, turnOn = true)
                        val updated = currentSchedule.copy(isCurrentlyBlocked = false)
                        repository.updateBedtimeSchedule(updated)
                        scheduleNextAlarms(context, updated)
                    }

                    Intent.ACTION_BOOT_COMPLETED,
                    ACTION_QUICKBOOT_POWERON -> {
                        Log.i(TAG, "Device booted. Evaluating bedtime state and scheduling alarms.")
                        val now = System.currentTimeMillis()
                        if (currentSchedule.isEnabled) {
                            val isBlocked = currentSchedule.isBedtimeActive(now)
                            if (isBlocked) {
                                Log.i(TAG, "Bedtime window active on boot; turning Wi-Fi OFF.")
                                WifiAccessibilityHelperService.requestToggle(context, turnOn = false)
                            } else if (currentSchedule.isCurrentlyBlocked) {
                                Log.i(TAG, "Bedtime window expired during reboot; turning Wi-Fi ON.")
                                WifiAccessibilityHelperService.requestToggle(context, turnOn = true)
                            }
                            val updated = currentSchedule.copy(isCurrentlyBlocked = isBlocked)
                            repository.updateBedtimeSchedule(updated)
                            scheduleNextAlarms(context, updated)
                        } else {
                            cancelAlarms(context)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing bedtime receiver event: $action", e)
            } finally {
                try {
                    if (wakeLock?.isHeld == true) {
                        wakeLock.release()
                    }
                } catch (ignored: Exception) {}
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val TAG = "BedtimeScheduleReceiver"

        const val ACTION_TRIGGER_BEDTIME = "com.familylink.buddy.child.ACTION_TRIGGER_BEDTIME"
        const val ACTION_TRIGGER_WAKEUP = "com.familylink.buddy.child.ACTION_TRIGGER_WAKEUP"
        const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"

        const val REQUEST_CODE_BEDTIME = 2001
        const val REQUEST_CODE_WAKEUP = 2002

        /**
         * Schedules the next exact alarms for bedtime and wakeup using AlarmManager.
         */
        fun scheduleNextAlarms(context: Context, schedule: BedtimeSchedule) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (alarmManager == null) {
                Log.e(TAG, "AlarmManager not available")
                return
            }

            if (!schedule.isEnabled || schedule.activeDays.isEmpty()) {
                Log.i(TAG, "Bedtime schedule disabled or activeDays empty. Canceling alarms.")
                cancelAlarms(context)
                return
            }

            val now = System.currentTimeMillis()
            val nextBedtimeMillis = schedule.getNextBedtimeMillis(now)
            val nextWakeupMillis = schedule.getNextWakeupMillis(now)

            Log.i(TAG, "Scheduling next alarms: bedtimeMillis=$nextBedtimeMillis, wakeupMillis=$nextWakeupMillis (now=$now)")

            // 1. Schedule next Bedtime alarm
            if (nextBedtimeMillis > now) {
                val bedtimeIntent = Intent(context, BedtimeScheduleReceiver::class.java).apply {
                    action = ACTION_TRIGGER_BEDTIME
                }
                val bedtimePi = PendingIntent.getBroadcast(
                    context,
                    REQUEST_CODE_BEDTIME,
                    bedtimeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setExactAlarm(alarmManager, nextBedtimeMillis, bedtimePi)
                Log.d(TAG, "Next Bedtime scheduled in ${(nextBedtimeMillis - now) / 1000} seconds")
            }

            // 2. Schedule next Wakeup alarm
            if (nextWakeupMillis > now) {
                val wakeupIntent = Intent(context, BedtimeScheduleReceiver::class.java).apply {
                    action = ACTION_TRIGGER_WAKEUP
                }
                val wakeupPi = PendingIntent.getBroadcast(
                    context,
                    REQUEST_CODE_WAKEUP,
                    wakeupIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setExactAlarm(alarmManager, nextWakeupMillis, wakeupPi)
                Log.d(TAG, "Next Wakeup scheduled in ${(nextWakeupMillis - now) / 1000} seconds")
            }
        }

        /**
         * Cancels any pending bedtime and wakeup alarms.
         */
        fun cancelAlarms(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

            val bedtimeIntent = Intent(context, BedtimeScheduleReceiver::class.java).apply {
                action = ACTION_TRIGGER_BEDTIME
            }
            val bedtimePi = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE_BEDTIME,
                bedtimeIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (bedtimePi != null) {
                alarmManager.cancel(bedtimePi)
                bedtimePi.cancel()
            }

            val wakeupIntent = Intent(context, BedtimeScheduleReceiver::class.java).apply {
                action = ACTION_TRIGGER_WAKEUP
            }
            val wakeupPi = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE_WAKEUP,
                wakeupIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (wakeupPi != null) {
                alarmManager.cancel(wakeupPi)
                wakeupPi.cancel()
            }
            Log.d(TAG, "Pending bedtime and wakeup alarms cancelled.")
        }

        private fun setExactAlarm(alarmManager: AlarmManager, triggerAtMillis: Long, pendingIntent: PendingIntent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }
        }
    }
}
