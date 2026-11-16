package com.familylink.buddy.child.service

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.familylink.buddy.child.data.AudioPlaybackManager
import com.familylink.buddy.child.data.ChatMessageRecord
import com.familylink.buddy.child.data.CommunicationDatabaseHelper

/**
 * Listens for incoming chat notifications from supported messaging platforms:
 * WhatsApp, Google Messages, Telegram, and Signal.
 */
class ChatNotificationListenerService : NotificationListenerService() {

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
        val isMediaSession = extras?.containsKey(Notification.EXTRA_MEDIA_SESSION) == true ||
                extras?.containsKey("android.mediaSession") == true
        val isTransport = notification.category == Notification.CATEGORY_TRANSPORT

        if (isMediaSession || isTransport || (!SUPPORTED_PACKAGES.contains(pkg) && AudioPlaybackManager.isMusicActive(this))) {
            val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
            val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
            val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()
            val artist = if (!text.isNullOrBlank()) text else subText
            if (!title.isNullOrBlank() || !artist.isNullOrBlank()) {
                AudioPlaybackManager.updateMediaInfo(title, artist, pkg)
            }
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
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "ChatNotificationListenerService connected and listening.")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.i(TAG, "ChatNotificationListenerService disconnected.")
    }
}
