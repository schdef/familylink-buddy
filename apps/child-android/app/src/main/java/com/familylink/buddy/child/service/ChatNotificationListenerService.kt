package com.familylink.buddy.child.service

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.familylink.buddy.child.data.AudioPlaybackManager
import com.familylink.buddy.child.data.ChatMessageRecord
import com.familylink.buddy.child.data.CommunicationDatabaseHelper

/**
 * Listens for incoming chat notifications from supported messaging platforms
 * (WhatsApp, Google Messages, Telegram, Signal) and monitors media session updates
 * for real-time track metadata detection.
 */
class ChatNotificationListenerService : NotificationListenerService() {

    private var sessionManager: MediaSessionManager? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val controllerCallbacks = mutableMapOf<MediaController, MediaController.Callback>()

    private val sessionsChangedListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        Log.d(TAG, "Active media sessions changed: count=${controllers?.size ?: 0}")
        updateMediaControllers(controllers)
        AudioPlaybackManager.refreshMediaInfo(this@ChatNotificationListenerService)
    }

    @Synchronized
    private fun updateMediaControllers(controllers: List<MediaController>?) {
        for ((controller, callback) in controllerCallbacks) {
            try {
                controller.unregisterCallback(callback)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering controller callback: ${e.message}")
            }
        }
        controllerCallbacks.clear()

        if (!controllers.isNullOrEmpty()) {
            for (controller in controllers) {
                val callback = object : MediaController.Callback() {
                    override fun onMetadataChanged(metadata: MediaMetadata?) {
                        Log.d(TAG, "Media metadata changed for package: ${controller.packageName}")
                        AudioPlaybackManager.refreshMediaInfo(this@ChatNotificationListenerService)
                    }

                    override fun onPlaybackStateChanged(state: PlaybackState?) {
                        Log.d(TAG, "Playback state changed for package: ${controller.packageName}, state=${state?.state}")
                        AudioPlaybackManager.refreshMediaInfo(this@ChatNotificationListenerService)
                    }
                }
                try {
                    controller.registerCallback(callback, mainHandler)
                    controllerCallbacks[controller] = callback
                } catch (e: Exception) {
                    Log.w(TAG, "Error registering callback on controller ${controller.packageName}: ${e.message}")
                }
            }
        }
    }

    private fun cleanupSessionListeners() {
        try {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        } catch (e: Exception) {
            Log.w(TAG, "Error removing active sessions listener: ${e.message}")
        }
        updateMediaControllers(null)
    }

    companion object {
        private const val TAG = "ChatNotifListener"

        const val PKG_WHATSAPP = "com.whatsapp"
        const val PKG_MESSAGES = "com.google.android.apps.messaging"
        const val PKG_TELEGRAM = "org.telegram.messenger"
        const val PKG_SIGNAL = "org.thoughtcrime.securesms"

        val SUPPORTED_PACKAGES = setOf(
            PKG_WHATSAPP,
            PKG_MESSAGES,
            PKG_TELEGRAM,
            PKG_SIGNAL
        )

        fun getFriendlyAppName(packageName: String): String {
            return when (packageName) {
                PKG_WHATSAPP -> "WhatsApp"
                PKG_MESSAGES -> "Messages"
                PKG_TELEGRAM -> "Telegram"
                PKG_SIGNAL -> "Signal"
                else -> packageName
            }
        }

        /**
         * Validates whether a notification is an authentic media playback notification
         * based on standard Android media criteria:
         * 1. EXTRA_MEDIA_SESSION or "android.mediaSession" extra key present
         * 2. MediaStyle template extra
         * 3. CATEGORY_TRANSPORT notification category
         * 4. Transport playback actions (play, pause, skip, next, previous)
         */
        fun isMediaNotification(
            category: String?,
            extras: Bundle?,
            actions: Array<Notification.Action>? = null
        ): Boolean {
            val hasMediaSessionExtra = extras?.containsKey(Notification.EXTRA_MEDIA_SESSION) == true ||
                    extras?.containsKey("android.mediaSession") == true
            val template = extras?.getString(Notification.EXTRA_TEMPLATE)
            val actionTitles = actions?.mapNotNull { it.title?.toString() }
            return isMediaNotification(category, hasMediaSessionExtra, template, actionTitles)
        }

        fun isMediaNotification(
            category: String?,
            hasMediaSessionExtra: Boolean,
            template: String?,
            actionTitles: List<String>? = null
        ): Boolean {
            if (hasMediaSessionExtra) return true
            if (template != null && template.contains("MediaStyle", ignoreCase = true)) return true
            if (category == Notification.CATEGORY_TRANSPORT) return true
            if (!actionTitles.isNullOrEmpty()) {
                val hasTransportAction = actionTitles.any { rawTitle ->
                    val title = rawTitle.lowercase()
                    title.contains("pause") || title.contains("play") || title.contains("next") ||
                            title.contains("previous") || title.contains("skip") || title.contains("stop")
                }
                if (hasTransportAction) return true
            }
            return false
        }

        /**
         * Parses notification title, text, and sender into a ChatMessageRecord.
         * Returns null if notification contains no meaningful message text or is a summary/ongoing service.
         */
        fun parseNotification(
            packageName: String,
            extras: Bundle?,
            postTime: Long
        ): ChatMessageRecord? {
            if (!SUPPORTED_PACKAGES.contains(packageName) || extras == null) {
                return null
            }

            // Extract conversation or sender title
            val conversationTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.trim()
            val rawTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
            val senderOrChat = when {
                !conversationTitle.isNullOrBlank() -> conversationTitle
                !rawTitle.isNullOrBlank() -> rawTitle
                else -> "Chat"
            }

            // Extract text body
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            val normalText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
            val text = when {
                !bigText.isNullOrBlank() -> bigText
                !normalText.isNullOrBlank() -> normalText
                else -> null
            }

            if (text.isNullOrBlank()) {
                return null
            }

            // Deduplicate ID based on package, postTime, sender, and text hash
            val contentHash = ((senderOrChat.hashCode() xor text.hashCode()) and 0x7FFFFFFF)
            val recordId = "chat_in_${packageName}_${postTime}_$contentHash"

            return ChatMessageRecord(
                id = recordId,
                appPackage = packageName,
                appName = getFriendlyAppName(packageName),
                senderOrChat = senderOrChat,
                text = text,
                isOutgoing = false,
                timestamp = if (postTime > 0) postTime else System.currentTimeMillis()
            )
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkg = sbn.packageName ?: return
        val notification = sbn.notification ?: return
        val extras = notification.extras

        // Media playback metadata extraction (Spotify, YouTube, Podcasting, etc.)
        val isMedia = isMediaNotification(notification.category, extras, notification.actions)
        if (isMedia) {
            val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
            val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
            val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()
            val artist = if (!text.isNullOrBlank()) text else subText
            if (!title.isNullOrBlank() || !artist.isNullOrBlank()) {
                AudioPlaybackManager.updateMediaInfo(title, artist, pkg)
            }
            AudioPlaybackManager.refreshMediaInfo(this)
        }

        // Chat messaging notification processing
        if (!SUPPORTED_PACKAGES.contains(pkg)) return

        val record = parseNotification(pkg, notification.extras, sbn.postTime)
        if (record != null) {
            Log.d(TAG, "Captured incoming chat from ${record.appName} (${record.senderOrChat}): ${record.text.take(30)}...")
            try {
                CommunicationDatabaseHelper.getInstance(applicationContext).insertChatMessage(record)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save incoming chat record: ${e.message}", e)
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == AudioPlaybackManager.currentMediaPackage) {
            if (!AudioPlaybackManager.isMusicActive(this)) {
                AudioPlaybackManager.clearMediaInfo()
            } else {
                AudioPlaybackManager.refreshMediaInfo(this)
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "ChatNotificationListenerService connected and listening.")
        try {
            sessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            val componentName = ComponentName(this, ChatNotificationListenerService::class.java)
            sessionManager?.addOnActiveSessionsChangedListener(sessionsChangedListener, componentName, mainHandler)
            val controllers = sessionManager?.getActiveSessions(componentName)
            updateMediaControllers(controllers)
            AudioPlaybackManager.refreshMediaInfo(this)
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException in onListenerConnected registering session listener: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Error in onListenerConnected media session setup: ${e.message}", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.i(TAG, "ChatNotificationListenerService disconnected.")
        cleanupSessionListeners()
    }

    override fun onDestroy() {
        super.onDestroy()
        cleanupSessionListeners()
    }
}
