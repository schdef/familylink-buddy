package com.familylink.buddy.child.data

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.util.Log
import android.view.KeyEvent
import org.json.JSONObject

object AudioPlaybackManager {
    private const val TAG = "AudioPlaybackManager"

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
}
