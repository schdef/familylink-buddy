package com.familylink.buddy.child.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.familylink.buddy.child.data.BedtimeSchedule
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.data.VolumeState
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.json.JSONArray
import com.familylink.buddy.child.data.AppUsage
import com.familylink.buddy.child.data.FamilyTimeData
import androidx.glance.appwidget.updateAll
import com.familylink.buddy.child.widget.FamilyBuddyWidget

class VolumeCommandService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "VolumeCommandService"
        private const val NOTIF_CHANNEL_ID = "volume_change"
        private const val NOTIF_ID = 9001

        // FCM message types
        const val TYPE_SET_VOLUME = "SET_VOLUME"
        const val TYPE_GET_VOLUME = "GET_VOLUME"
        const val TYPE_SCREEN_TIME_UPDATE = "SCREEN_TIME_UPDATE"
        const val TYPE_SET_SCHEDULE = "SET_SCHEDULE"
        const val TYPE_TOGGLE_WIFI = "TOGGLE_WIFI"

        // Volume stream names
        const val STREAM_MEDIA = "MEDIA"
        const val STREAM_RINGTONE = "RINGTONE"
        const val STREAM_ALARM = "ALARM"
        const val STREAM_ALL = "ALL"
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "FCM token refreshed: $token")
        // Persist new token to DataStore
        serviceScope.launch {
            val repo = FamilyTimeRepository(applicationContext)
            repo.updateDeviceToken(token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "FamilyLinkBuddy:VolumeCommandLock"
        )?.apply {
            acquire(5000L) // Max 5s
        }

        try {
            val data = message.data
            val type = data["type"] ?: return
            Log.d(TAG, "FCM message received: type=$type, data=$data")

            when (type) {
                TYPE_SET_VOLUME -> handleSetVolume(data)
                TYPE_GET_VOLUME -> reportVolumeToParent(data["parentToken"])
                TYPE_SCREEN_TIME_UPDATE -> handleScreenTimeUpdate(data)
                TYPE_SET_SCHEDULE -> handleSetSchedule(data)
                TYPE_TOGGLE_WIFI -> handleToggleWifi(data)
                else -> Log.w(TAG, "Unknown FCM message type: $type")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling FCM message", e)
        } finally {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock.release()
                }
            } catch (ignored: Exception) {}
        }
    }

    private fun handleScreenTimeUpdate(data: Map<String, String>) {
        val remaining = data["totalRemainingMinutes"]?.toIntOrNull() ?: return
        val limit = data["totalLimitMinutes"]?.toIntOrNull() ?: 120
        val appUsagesJsonStr = data["appUsages"] ?: "[]"

        val appUsages = mutableListOf<AppUsage>()
        try {
            val jsonArray = JSONArray(appUsagesJsonStr)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                appUsages.add(
                    AppUsage(
                        packageName = obj.getString("packageName"),
                        appName = obj.getString("appName"),
                        usedMinutes = obj.getInt("usedMinutes"),
                        limitMinutes = obj.getInt("limitMinutes")
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing appUsages from FCM", e)
        }

        val updatedData = FamilyTimeData(
            totalRemainingMinutes = remaining,
            totalLimitMinutes = limit,
            lastUpdatedMillis = System.currentTimeMillis(),
            appUsages = appUsages
        )

        serviceScope.launch {
            val repo = FamilyTimeRepository(applicationContext)
            repo.updateFamilyTimeData(updatedData)
            // Trigger widget redraw
            FamilyBuddyWidget().updateAll(applicationContext)
            Log.d(TAG, "Screen time updated from FCM: $remaining mins remaining")
        }
    }

    private fun handleSetSchedule(data: Map<String, String>) {
        val scheduleJson = data["schedule"]
        val schedule = if (!scheduleJson.isNullOrBlank()) {
            BedtimeSchedule.fromJson(scheduleJson)
        } else {
            val isEnabled = data["enabled"]?.toBoolean() ?: data["isEnabled"]?.toBoolean() ?: true
            val bedtimeHour = data["bedtimeHour"]?.toIntOrNull() ?: 20
            val bedtimeMinute = data["bedtimeMinute"]?.toIntOrNull() ?: 30
            val wakeupHour = data["wakeupHour"]?.toIntOrNull() ?: 6
            val wakeupMinute = data["wakeupMinute"]?.toIntOrNull() ?: 45
            val activeDaysStr = data["activeDays"]
            val activeDays = if (!activeDaysStr.isNullOrBlank()) {
                if (activeDaysStr.startsWith("[")) {
                    try {
                        val arr = JSONArray(activeDaysStr)
                        (0 until arr.length()).map { arr.getInt(it) }
                    } catch (e: Exception) {
                        listOf(1, 2, 3, 4, 5, 6, 7)
                    }
                } else {
                    activeDaysStr.split(",").mapNotNull { it.trim().toIntOrNull() }
                }
            } else {
                listOf(1, 2, 3, 4, 5, 6, 7)
            }

            BedtimeSchedule(
                isEnabled = isEnabled,
                bedtimeHour = bedtimeHour,
                bedtimeMinute = bedtimeMinute,
                wakeupHour = wakeupHour,
                wakeupMinute = wakeupMinute,
                activeDays = if (activeDays.isNotEmpty()) activeDays else listOf(1, 2, 3, 4, 5, 6, 7)
            )
        }

        serviceScope.launch {
            val repo = FamilyTimeRepository(applicationContext)
            repo.updateBedtimeSchedule(schedule)
            BedtimeScheduleReceiver.scheduleNextAlarms(applicationContext, schedule)
            Log.d(TAG, "Bedtime schedule updated from FCM: $schedule")
        }
    }

    private fun handleToggleWifi(data: Map<String, String>) {
        val block = data["block"]?.equals("true", ignoreCase = true) == true || data["block"] == "1"
        val turnOn = if (data.containsKey("turnOn")) {
            data["turnOn"]?.equals("true", ignoreCase = true) == true || data["turnOn"] == "1"
        } else {
            !block
        }
        Log.i(TAG, "FCM Wi-Fi toggle request: turnOn=$turnOn")
        WifiAccessibilityHelperService.requestToggle(applicationContext, turnOn)
    }

    private fun handleSetVolume(data: Map<String, String>) {
        val stream = data["stream"] ?: STREAM_MEDIA
        val level = data["level"]?.toIntOrNull() ?: return
        val parentToken = data["parentToken"]

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        when (stream) {
            STREAM_MEDIA -> setVolume(audioManager, AudioManager.STREAM_MUSIC, level)
            STREAM_RINGTONE -> setVolume(audioManager, AudioManager.STREAM_RING, level)
            STREAM_ALARM -> setVolume(audioManager, AudioManager.STREAM_ALARM, level)
            STREAM_ALL -> {
                setVolume(audioManager, AudioManager.STREAM_MUSIC, level)
                setVolume(audioManager, AudioManager.STREAM_RING, level)
                setVolume(audioManager, AudioManager.STREAM_ALARM, level)
            }
        }

        // Show transparency notification to child
        showVolumeChangedNotification(stream, level)

        // Persist new volume state
        serviceScope.launch {
            val repo = FamilyTimeRepository(applicationContext)
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val state = readCurrentVolumeState(audio)
            repo.updateVolumeState(state)
            // Report back to parent if token provided
            if (!parentToken.isNullOrEmpty()) {
                sendVolumeReport(parentToken, state)
            }
        }
    }

    private fun setVolume(audioManager: AudioManager, stream: Int, level: Int) {
        try {
            if (stream == AudioManager.STREAM_RING && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (notificationManager?.isNotificationPolicyAccessGranted != true) {
                    Log.w(TAG, "Skipping STREAM_RING: DND access not granted")
                    return
                }
            }
            val max = audioManager.getStreamMaxVolume(stream)
            val clamped = level.coerceIn(0, max)
            audioManager.setStreamVolume(stream, clamped, 0)
            Log.d(TAG, "Set stream $stream to $clamped (max $max)")
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException setting stream $stream volume (likely DND): ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set volume for stream $stream: ${e.message}", e)
        }
    }

    private fun reportVolumeToParent(parentToken: String?) {
        if (parentToken.isNullOrEmpty()) return
        serviceScope.launch {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val state = readCurrentVolumeState(audioManager)
            sendVolumeReport(parentToken, state)
        }
    }

    private fun readCurrentVolumeState(audioManager: AudioManager): VolumeState {
        val media = try { audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) } catch (e: Exception) { 0 }
        val ring = try { audioManager.getStreamVolume(AudioManager.STREAM_RING) } catch (e: Exception) { 0 }
        val alarm = try { audioManager.getStreamVolume(AudioManager.STREAM_ALARM) } catch (e: Exception) { 0 }
        val maxMedia = try { audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC) } catch (e: Exception) { 15 }
        val maxRing = try { audioManager.getStreamMaxVolume(AudioManager.STREAM_RING) } catch (e: Exception) { 15 }
        val maxAlarm = try { audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM) } catch (e: Exception) { 15 }
        return VolumeState(
            mediaVolume = media,
            ringtoneVolume = ring,
            alarmVolume = alarm,
            maxMediaVolume = maxMedia,
            maxRingtoneVolume = maxRing,
            maxAlarmVolume = maxAlarm,
            isMuted = media == 0
        )
    }

    private fun sendVolumeReport(parentToken: String, state: VolumeState) {
        val payload = JSONObject().apply {
            put("type", "VOLUME_REPORT")
            put("mediaVolume", state.mediaVolume)
            put("ringtoneVolume", state.ringtoneVolume)
            put("alarmVolume", state.alarmVolume)
            put("maxMediaVolume", state.maxMediaVolume)
            put("maxRingtoneVolume", state.maxRingtoneVolume)
            put("maxAlarmVolume", state.maxAlarmVolume)
            put("isMuted", state.isMuted)
            put("timestamp", System.currentTimeMillis())
        }
        Log.d(TAG, "Volume report payload: $payload (to: $parentToken)")
    }

    private fun showVolumeChangedNotification(stream: String, level: Int) {
        createNotificationChannel()
        val streamName = when (stream) {
            STREAM_MEDIA -> getString(com.familylink.buddy.child.R.string.volume_stream_media)
            STREAM_RINGTONE -> getString(com.familylink.buddy.child.R.string.volume_stream_ringtone)
            STREAM_ALARM -> getString(com.familylink.buddy.child.R.string.volume_stream_alarm)
            else -> getString(com.familylink.buddy.child.R.string.volume_stream_all)
        }
        val notification = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
            .setContentTitle(getString(com.familylink.buddy.child.R.string.volume_changed_title))
            .setContentText(getString(com.familylink.buddy.child.R.string.volume_changed_body, streamName, level))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                getString(com.familylink.buddy.child.R.string.volume_notif_channel_name),
                NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
