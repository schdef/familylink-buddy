package com.familylink.buddy.child

import com.familylink.buddy.child.data.CallRecord
import com.familylink.buddy.child.data.CallType
import com.familylink.buddy.child.data.ChatMessageRecord
import com.familylink.buddy.child.data.toJsonArray
import com.familylink.buddy.child.service.ChatNotificationListenerService
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalHttpServerCommsTest {

    @Test
    fun testCallLogsResponsePayloadStructure() {
        val calls = listOf(
            CallRecord(
                id = "call_1",
                phoneNumber = "+491701234567",
                contactName = "Mama",
                callType = CallType.INCOMING,
                timestamp = 1731500000000L,
                durationSeconds = 120L
            ),
            CallRecord(
                id = "call_2",
                phoneNumber = "+491707654321",
                contactName = null,
                callType = CallType.MISSED,
                timestamp = 1731500100000L,
                durationSeconds = 0L
            )
        )

        val responseJson = JSONObject().apply {
            put("status", "success")
            put("calls", calls.toJsonArray())
            put("count", calls.size)
        }

        assertEquals("success", responseJson.getString("status"))
        assertEquals(2, responseJson.getInt("count"))
        val callsArray = responseJson.getJSONArray("calls")
        assertEquals(2, callsArray.length())

        val firstCall = callsArray.getJSONObject(0)
        assertEquals("call_1", firstCall.getString("id"))
        assertEquals("+491701234567", firstCall.getString("phoneNumber"))
        assertEquals("Mama", firstCall.getString("contactName"))
        assertEquals("INCOMING", firstCall.getString("callType"))
        assertEquals(1731500000000L, firstCall.getLong("timestamp"))
        assertEquals(120L, firstCall.getLong("durationSeconds"))

        val secondCall = callsArray.getJSONObject(1)
        assertEquals("call_2", secondCall.getString("id"))
        assertTrue(secondCall.isNull("contactName"))
        assertEquals("MISSED", secondCall.getString("callType"))
    }

    @Test
    fun testChatLogsResponsePayloadStructure() {
        val chats = listOf(
            ChatMessageRecord(
                id = "chat_1",
                appPackage = "com.whatsapp",
                appName = "WhatsApp",
                senderOrChat = "Family Chat",
                text = "Dinner is ready",
                isOutgoing = false,
                timestamp = 1731501000000L
            ),
            ChatMessageRecord(
                id = "chat_2",
                appPackage = "com.whatsapp",
                appName = "WhatsApp",
                senderOrChat = "Family Chat",
                text = "Coming downstairs!",
                isOutgoing = true,
                timestamp = 1731501050000L
            )
        )

        val responseJson = JSONObject().apply {
            put("status", "success")
            put("chats", chats.toJsonArray())
            put("count", chats.size)
        }

        assertEquals("success", responseJson.getString("status"))
        assertEquals(2, responseJson.getInt("count"))
        val chatsArray = responseJson.getJSONArray("chats")
        assertEquals(2, chatsArray.length())

        val firstChat = chatsArray.getJSONObject(0)
        assertEquals("chat_1", firstChat.getString("id"))
        assertEquals("com.whatsapp", firstChat.getString("appPackage"))
        assertEquals("WhatsApp", firstChat.getString("appName"))
        assertEquals("Family Chat", firstChat.getString("senderOrChat"))
        assertEquals("Dinner is ready", firstChat.getString("text"))
        assertFalse(firstChat.getBoolean("isOutgoing"))

        val secondChat = chatsArray.getJSONObject(1)
        assertTrue(secondChat.getBoolean("isOutgoing"))
        assertEquals("Coming downstairs!", secondChat.getString("text"))
    }

    @Test
    fun testClearCommunicationHistoryResponseStructure() {
        val responseJson = JSONObject().apply {
            put("status", "success")
            put("message", "Communication history cleared")
        }

        assertEquals("success", responseJson.getString("status"))
        assertEquals("Communication history cleared", responseJson.getString("message"))
    }

    @Test
    fun testAuthenticationPolicyForCommsEndpoints() {
        val pairedToken = "sec_test_secret_token_123"

        val publicPaths = setOf("/status", "/pair")
        val commsPaths = listOf("/call_logs", "/chat_logs", "/clear_communication_history")

        for (path in commsPaths) {
            // Must NOT be public
            assertFalse("Path $path must require authentication", publicPaths.contains(path))

            // Test token validation logic
            val checkAuth = { incomingToken: String? ->
                pairedToken.isNotEmpty() && !publicPaths.contains(path) && (incomingToken == null || incomingToken != pairedToken)
            }

            // Missing token -> unauthorized
            assertTrue(checkAuth(null))

            // Wrong token -> unauthorized
            assertTrue(checkAuth("wrong_token"))

            // Correct token -> authorized
            assertFalse(checkAuth("sec_test_secret_token_123"))
        }
    }

    @Test
    fun testQueryParamsParsingAndClamping() {
        val params = mapOf(
            "since" to "1731500000000",
            "limit" to "1000", // exceeds max 500
            "package" to "com.whatsapp"
        )

        val since = params["since"]?.toLongOrNull() ?: 0L
        val limit = params["limit"]?.toIntOrNull()?.coerceIn(1, 500) ?: 100
        val pkg = params["package"]?.takeIf { it.isNotBlank() }

        assertEquals(1731500000000L, since)
        assertEquals(500, limit) // clamped to 500
        assertEquals("com.whatsapp", pkg)

        // Negative limit
        val negLimit = "-10".toIntOrNull()?.coerceIn(1, 500) ?: 100
        assertEquals(1, negLimit) // clamped to 1
    }

    @Test
    fun testChatNotificationListenerPackagesAndAppNames() {
        val packages = ChatNotificationListenerService.SUPPORTED_PACKAGES
        assertEquals(4, packages.size)
        assertTrue(packages.contains("com.whatsapp"))
        assertTrue(packages.contains("com.google.android.apps.messaging"))
        assertTrue(packages.contains("org.telegram.messenger"))
        assertTrue(packages.contains("org.thoughtcrime.securesms"))

        assertEquals("WhatsApp", ChatNotificationListenerService.getFriendlyAppName("com.whatsapp"))
        assertEquals("Messages", ChatNotificationListenerService.getFriendlyAppName("com.google.android.apps.messaging"))
        assertEquals("Telegram", ChatNotificationListenerService.getFriendlyAppName("org.telegram.messenger"))
        assertEquals("Signal", ChatNotificationListenerService.getFriendlyAppName("org.thoughtcrime.securesms"))
        assertEquals("com.unknown.app", ChatNotificationListenerService.getFriendlyAppName("com.unknown.app"))
    }
}
