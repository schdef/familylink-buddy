package com.familylink.buddy.child.data

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import com.familylink.buddy.child.service.ChatNotificationListenerService
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AudioPlaybackManager {
    private const val TAG = "AudioPlaybackManager"

    val ACTIVE_PLAYBACK_STATES = setOf(
        PlaybackState.STATE_PLAYING,
        PlaybackState.STATE_BUFFERING,
        PlaybackState.STATE_SKIPPING_TO_NEXT,
        PlaybackState.STATE_FAST_FORWARDING
    )

    @Volatile
    var currentMediaTitle: String? = null

    @Volatile
    var currentMediaArtist: String? = null

    @Volatile
    var currentMediaPackage: String? = null

    @Volatile
    var lastMediaUpdateTime: Long = 0L

    fun updateMediaInfo(title: String?, artist: String?, pkg: String?) {
        val cleanTitle = title?.trim()?.takeIf { it.isNotBlank() }
        val cleanArtist = artist?.trim()?.takeIf { it.isNotBlank() }
        if (cleanTitle != null || cleanArtist != null) {
            currentMediaTitle = cleanTitle
            currentMediaArtist = cleanArtist
            currentMediaPackage = pkg
            lastMediaUpdateTime = System.currentTimeMillis()
        }
    }

    fun clearMediaInfo() {
        currentMediaTitle = null
        currentMediaArtist = null
        currentMediaPackage = null
    }

    fun extractTitle(
        titleString: String?,
        displayTitleString: String?,
        titleText: CharSequence? = null,
        displayTitleText: CharSequence? = null
    ): String? {
        return titleString?.trim()?.takeIf { it.isNotBlank() }
            ?: displayTitleString?.trim()?.takeIf { it.isNotBlank() }
            ?: titleText?.toString()?.trim()?.takeIf { it.isNotBlank() }
            ?: displayTitleText?.toString()?.trim()?.takeIf { it.isNotBlank() }
    }

    fun extractArtist(
        artistString: String?,
        albumArtistString: String?,
        displaySubtitleString: String?,
        authorString: String?,
        artistText: CharSequence? = null
    ): String? {
        return artistString?.trim()?.takeIf { it.isNotBlank() }
            ?: albumArtistString?.trim()?.takeIf { it.isNotBlank() }
            ?: displaySubtitleString?.trim()?.takeIf { it.isNotBlank() }
            ?: authorString?.trim()?.takeIf { it.isNotBlank() }
            ?: artistText?.toString()?.trim()?.takeIf { it.isNotBlank() }
    }

    data class PlaybackControllerInfo(
        val packageName: String,
        val playbackState: Int,
        val title: String? = null,
        val artist: String? = null
    )

    fun selectTargetControllerInfo(
        controllers: List<PlaybackControllerInfo>,
        currentPackage: String?,
        isAudioActive: Boolean
    ): PlaybackControllerInfo? {
        if (currentPackage != null) {
            val matching = controllers.firstOrNull {
                it.packageName == currentPackage && (it.playbackState in ACTIVE_PLAYBACK_STATES)
            }
            if (matching != null) return matching
        }
        val active = controllers.firstOrNull {
            it.playbackState in ACTIVE_PLAYBACK_STATES
        }
        if (active != null) return active

        return if (isAudioActive) controllers.firstOrNull() else null
    }

    /**
     * Actively queries MediaSessionManager to refresh title, artist, and package name
     * for active playback sessions.
     */
    fun refreshMediaInfo(context: Context) {
        try {
            val sessionManager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return
            val componentName = ComponentName(context, ChatNotificationListenerService::class.java)
            val controllers: List<MediaController> = try {
                sessionManager.getActiveSessions(componentName)
            } catch (e: SecurityException) {
                Log.w(TAG, "SecurityException calling getActiveSessions: ${e.message}")
                return
            } catch (e: Exception) {
                Log.e(TAG, "Exception calling getActiveSessions: ${e.message}")
                return
            }

            val isAudioActive = isMusicActive(context)

            if (controllers.isNullOrEmpty()) {
                if (!isAudioActive) {
                    clearMediaInfo()
                }
                return
            }

            var targetController: MediaController? = null
            val currentPkg = currentMediaPackage
            if (currentPkg != null) {
                targetController = controllers.firstOrNull { controller ->
                    controller.packageName == currentPkg && (controller.playbackState?.state in ACTIVE_PLAYBACK_STATES)
                }
            }
            if (targetController == null) {
                targetController = controllers.firstOrNull { controller ->
                    controller.playbackState?.state in ACTIVE_PLAYBACK_STATES
                }
            }
            if (targetController == null && isAudioActive) {
                targetController = controllers.firstOrNull()
            }

            val hasActiveController = controllers.any { it.playbackState?.state in ACTIVE_PLAYBACK_STATES }
            if (!isAudioActive && !hasActiveController) {
                clearMediaInfo()
                return
            }

            if (targetController != null) {
                val metadata = targetController.metadata
                if (metadata != null) {
                    val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                        ?: metadata.getText(MediaMetadata.METADATA_KEY_TITLE)?.toString()
                        ?: metadata.getText(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)?.toString()

                    val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_AUTHOR)
                        ?: metadata.getText(MediaMetadata.METADATA_KEY_ARTIST)?.toString()

                    val pkg = targetController.packageName
                    if (!title.isNullOrBlank() || !artist.isNullOrBlank()) {
                        updateMediaInfo(title, artist, pkg)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh media info: ${e.message}", e)
        }
    }

    /**
     * Checks whether any audio playback (music/media) is currently active on the device.
     */
    fun isMusicActive(context: Context): Boolean {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioManager?.isMusicActive ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking isMusicActive: ${e.message}", e)
            false
        }
    }

    /**
     * Attempts to remotely pause/stop active media playback across all background audio players
     * (e.g., Spotify, YouTube, Podcast players).
     *
     * 1. Requests transient audio focus and immediately abandons it to signal media apps to pause.
     * 2. Dispatches explicit MEDIA_PAUSE (down/up) and MEDIA_STOP (down/up) key events.
     *
     * @return true if commands were successfully dispatched, false otherwise.
     */
    fun stopPlayback(context: Context): Boolean {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return false
            stopPlayback(audioManager)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop playback: ${e.message}", e)
            false
        }
    }

    /**
     * Overload accepting AudioManager directly for modularity and testability.
     */
    fun stopPlayback(audioManager: AudioManager): Boolean {
        return try {
            // 1. Request transient audio focus then abandon it
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val playbackAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()

                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(playbackAttributes)
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener { /* no-op */ }
                    .build()

                val focusResult = audioManager.requestAudioFocus(focusRequest)
                Log.d(TAG, "Transient audio focus request result: $focusResult")
                audioManager.abandonAudioFocusRequest(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                val focusResult = audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
                Log.d(TAG, "Legacy transient audio focus result: $focusResult")
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }

            // 2. Dispatch MEDIA_PAUSE (down & up)
            val eventTime = System.currentTimeMillis()
            val pauseDown = KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE, 0)
            val pauseUp = KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE, 0)
            audioManager.dispatchMediaKeyEvent(pauseDown)
            audioManager.dispatchMediaKeyEvent(pauseUp)

            // 3. Dispatch MEDIA_STOP (down & up)
            val stopDown = KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_STOP, 0)
            val stopUp = KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_STOP, 0)
            audioManager.dispatchMediaKeyEvent(stopDown)
            audioManager.dispatchMediaKeyEvent(stopUp)

            clearMediaInfo()

            Log.i(TAG, "Successfully dispatched audio stop and pause commands")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error executing stopPlayback on AudioManager: ${e.message}", e)
            false
        }
    }

    /**
     * Helper to construct response JSON for stop_audio endpoint.
     */
    fun buildStopAudioResponse(isMusicActive: Boolean = false): JSONObject {
        return JSONObject().apply {
            put("status", "success")
            put("isMusicActive", isMusicActive)
        }
    }

    /**
     * Maps user-facing stream string ("MEDIA", "RINGTONE", "ALARM", "ALL") to AudioManager stream constants.
     */
    fun mapStreamType(stream: String?): Int {
        return when (stream?.uppercase()) {
            "RINGTONE" -> AudioManager.STREAM_RING
            "ALARM" -> AudioManager.STREAM_ALARM
            "MEDIA" -> AudioManager.STREAM_MUSIC
            else -> AudioManager.STREAM_MUSIC
        }
    }

    /**
     * Safely parses stream parameter from optional JSON body and query parameters.
     */
    fun parseStreamParam(bodyJson: JSONObject?, queryParams: Map<String, String>): String {
        return bodyJson?.optString("stream")?.takeIf { it.isNotBlank() }
            ?: queryParams["stream"]?.takeIf { it.isNotBlank() }
            ?: "MEDIA"
    }

    /**
     * Safely parses level parameter from optional JSON body and query parameters.
     */
    fun parseLevelParam(bodyJson: JSONObject?, queryParams: Map<String, String>): Int {
        return when {
            bodyJson != null && bodyJson.has("level") && !bodyJson.isNull("level") -> bodyJson.optInt("level", 0)
            queryParams.containsKey("level") -> queryParams["level"]?.toIntOrNull() ?: 0
            else -> 0
        }
    }

    /**
     * Sets volume for a specific stream type with full Android M+ unmute/mute logic, DND safety, and HUD UI flags.
     */
    fun setStreamVolume(
        context: Context,
        audioManager: AudioManager,
        streamType: Int,
        level: Int,
        flags: Int = AudioManager.FLAG_SHOW_UI
    ) {
        try {
            if (streamType == AudioManager.STREAM_RING && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (notificationManager?.isNotificationPolicyAccessGranted != true) {
                    Log.w(TAG, "Skipping STREAM_RING: DND access not granted")
                    return
                }
            }

            val max = audioManager.getStreamMaxVolume(streamType)
            val clamped = level.coerceIn(0, max)
            val currentVol = audioManager.getStreamVolume(streamType)
            val isCurrentlyMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioManager.isStreamMute(streamType) || currentVol == 0
            } else {
                currentVol == 0
            }

            if (clamped == 0) {
                audioManager.setStreamVolume(streamType, 0, flags)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        audioManager.adjustStreamVolume(streamType, AudioManager.ADJUST_MUTE, flags)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to adjustStreamVolume ADJUST_MUTE for $streamType: ${e.message}")
                    }
                }
            } else {
                if (isCurrentlyMuted && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        audioManager.adjustStreamVolume(streamType, AudioManager.ADJUST_UNMUTE, 0)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to adjustStreamVolume ADJUST_UNMUTE for $streamType: ${e.message}")
                    }
                }
                audioManager.setStreamVolume(streamType, clamped, flags)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException setting stream $streamType volume (likely DND): ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting stream volume for $streamType: ${e.message}", e)
        }
    }

    /**
     * Dispatches volume adjustment on the Android Main Looper (to avoid OEM ROMs dropping background audio mixer commands)
     * and waits for completion.
     */
    fun applyVolumeChangeOnMainLooper(
        context: Context,
        stream: String,
        level: Int,
        flags: Int = AudioManager.FLAG_SHOW_UI,
        timeoutMs: Long = 1500L
    ) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val runnable = Runnable {
            if (stream.equals("ALL", ignoreCase = true)) {
                setStreamVolume(context, audioManager, AudioManager.STREAM_MUSIC, level, flags)
                setStreamVolume(context, audioManager, AudioManager.STREAM_RING, level, flags)
                setStreamVolume(context, audioManager, AudioManager.STREAM_ALARM, level, flags)
            } else {
                val streamType = mapStreamType(stream)
                setStreamVolume(context, audioManager, streamType, level, flags)
            }
        }

        try {
            val mainLooper = Looper.getMainLooper()
            if (mainLooper != null && Looper.myLooper() == mainLooper) {
                runnable.run()
            } else if (mainLooper != null) {
                val latch = CountDownLatch(1)
                Handler(mainLooper).post {
                    try {
                        runnable.run()
                    } finally {
                        latch.countDown()
                    }
                }
                latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            } else {
                runnable.run()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing volume change on main looper", e)
            runnable.run()
        }
    }

    /**
     * Builds updated volume response payload for /set_volume endpoint.
     */
    fun buildSetVolumeResponse(
        stream: String,
        level: Int,
        state: VolumeState
    ): JSONObject {
        return JSONObject().apply {
            put("status", "success")
            put("stream", stream)
            put("level", level)
            put("mediaVolume", state.mediaVolume)
            put("ringtoneVolume", state.ringtoneVolume)
            put("alarmVolume", state.alarmVolume)
            put("maxMediaVolume", state.maxMediaVolume)
            put("maxRingtoneVolume", state.maxRingtoneVolume)
            put("maxAlarmVolume", state.maxAlarmVolume)
            put("isMuted", state.isMuted)
            put("isMusicActive", state.isMusicActive)
            if (state.isMusicActive) {
                put("mediaTitle", currentMediaTitle ?: "")
                put("mediaArtist", currentMediaArtist ?: "")
                put("mediaPackage", currentMediaPackage ?: "")
            }
            put("timestamp", System.currentTimeMillis())
        }
    }
}
