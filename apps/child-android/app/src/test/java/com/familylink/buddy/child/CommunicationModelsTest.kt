package com.familylink.buddy.child

import com.familylink.buddy.child.data.CallRecord
import com.familylink.buddy.child.data.CallType
import com.familylink.buddy.child.data.ChatMessageRecord
import com.familylink.buddy.child.data.parseCallRecords
import com.familylink.buddy.child.data.parseChatMessageRecords
import com.familylink.buddy.child.data.toJsonArray
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CommunicationModelsTest {

    @Test
    fun testCallTypeFromString() {
        assertEquals(CallType.INCOMING, CallType.fromString("INCOMING"))
        assertEquals(CallType.OUTGOING, CallType.fromString("OUTGOING"))
        assertEquals(CallType.MISSED, CallType.fromString("MISSED"))
        assertEquals(CallType.REJECTED, CallType.fromString("REJECTED"))

        // Case insensitivity & trimming
        assertEquals(CallType.INCOMING, CallType.fromString("incoming "))
        assertEquals(CallType.MISSED, CallType.fromString(" missed"))

        // Fallbacks
        assertEquals(CallType.INCOMING, CallType.fromString(null))
        assertEquals(CallType.INCOMING, CallType.fromString("UNKNOWN"))
    }

    @Test
    fun testCallTypeFromCallLogType() {
        assertEquals(CallType.INCOMING, CallType.fromCallLogType(1))
        assertEquals(CallType.OUTGOING, CallType.fromCallLogType(2))
        assertEquals(CallType.MISSED, CallType.fromCallLogType(3))
        assertEquals(CallType.REJECTED, CallType.fromCallLogType(5))
        assertEquals(CallType.REJECTED, CallType.fromCallLogType(6)) // Blocked
        assertEquals(CallType.INCOMING, CallType.fromCallLogType(99)) // Unknown fallback
    }

    @Test
    fun testCallRecordSerializationWithContact() {
        val record = CallRecord(
            id = "call_123",
            phoneNumber = "+491701234567",
            contactName = "Mama",
            callType = CallType.INCOMING,
            timestamp = 1731500000000L,
            durationSeconds = 120L
        )

        val json = record.toJson()
        assertEquals("call_123", json.getString("id"))
        assertEquals("+491701234567", json.getString("phoneNumber"))
        assertEquals("Mama", json.getString("contactName"))
        assertEquals("INCOMING", json.getString("callType"))
        assertEquals(1731500000000L, json.getLong("timestamp"))
        assertEquals(120L, json.getLong("durationSeconds"))

        val parsed = CallRecord.fromJson(json)
        assertEquals(record.id, parsed.id)
        assertEquals(record.phoneNumber, parsed.phoneNumber)
        assertEquals(record.contactName, parsed.contactName)
        assertEquals(record.callType, parsed.callType)
        assertEquals(record.timestamp, parsed.timestamp)
        assertEquals(record.durationSeconds, parsed.durationSeconds)
    }

    @Test
    fun testCallRecordSerializationWithoutContact() {
        val record = CallRecord(
            id = "call_456",
            phoneNumber = "+491709876543",
            contactName = null,
            callType = CallType.MISSED,
            timestamp = 1731500500000L,
            durationSeconds = 0L
        )

        val json = record.toJson()
        assertTrue(json.isNull("contactName"))

        val parsed = CallRecord.fromJson(json)
        assertNull(parsed.contactName)
        assertEquals(CallType.MISSED, parsed.callType)
    }

    @Test
    fun testChatMessageRecordSerializationIncoming() {
        val record = ChatMessageRecord(
            id = "msg_001",
            appPackage = "com.whatsapp",
            appName = "WhatsApp",
            senderOrChat = "Family Chat",
            text = "Are you home yet?",
            isOutgoing = false,
            timestamp = 1731501000000L
        )

        val json = record.toJson()
        assertEquals("msg_001", json.getString("id"))
        assertEquals("com.whatsapp", json.getString("appPackage"))
        assertEquals("WhatsApp", json.getString("appName"))
        assertEquals("Family Chat", json.getString("senderOrChat"))
        assertEquals("Are you home yet?", json.getString("text"))
        assertFalse(json.getBoolean("isOutgoing"))
        assertEquals(1731501000000L, json.getLong("timestamp"))

        val parsed = ChatMessageRecord.fromJson(json)
        assertEquals(record.id, parsed.id)
        assertEquals(record.appPackage, parsed.appPackage)
        assertEquals(record.appName, parsed.appName)
        assertEquals(record.senderOrChat, parsed.senderOrChat)
        assertEquals(record.text, parsed.text)
        assertEquals(record.isOutgoing, parsed.isOutgoing)
        assertEquals(record.timestamp, parsed.timestamp)
    }

    @Test
    fun testChatMessageRecordSerializationOutgoing() {
        val record = ChatMessageRecord(
            id = "msg_002",
            appPackage = "org.telegram.messenger",
            appName = "Telegram",
            senderOrChat = "Oma",
            text = "Ja, ich mache gerade Hausaufgaben!",
            isOutgoing = true,
            timestamp = 1731501050000L
        )

        val json = record.toJson()
        assertTrue(json.getBoolean("isOutgoing"))

        val parsed = ChatMessageRecord.fromJson(json)
        assertTrue(parsed.isOutgoing)
        assertEquals("Oma", parsed.senderOrChat)
        assertEquals("Ja, ich mache gerade Hausaufgaben!", parsed.text)
    }

    @Test
    fun testCallRecordListJsonHelpers() {
        val records = listOf(
            CallRecord(
                id = "call_1",
                phoneNumber = "111",
                contactName = "Alice",
                callType = CallType.OUTGOING,
                timestamp = 1000L,
                durationSeconds = 40L
            ),
            CallRecord(
                id = "call_2",
                phoneNumber = "222",
                contactName = null,
                callType = CallType.REJECTED,
                timestamp = 2000L,
                durationSeconds = 0L
            )
        )

        val jsonArray = records.toJsonArray()
        assertEquals(2, jsonArray.length())

        val parsedList = parseCallRecords(jsonArray)
        assertEquals(2, parsedList.size)
        assertEquals("Alice", parsedList[0].contactName)
        assertEquals(CallType.OUTGOING, parsedList[0].callType)
        assertNull(parsedList[1].contactName)
        assertEquals(CallType.REJECTED, parsedList[1].callType)

        // Empty list check
        val emptyArray = emptyList<CallRecord>().toJsonArray()
        assertEquals(0, emptyArray.length())
        assertTrue(parseCallRecords(emptyArray).isEmpty())
    }

    @Test
    fun testChatMessageRecordListJsonHelpers() {
        val records = listOf(
            ChatMessageRecord(
                id = "m1",
                appPackage = "com.google.android.apps.messaging",
                appName = "Messages",
                senderOrChat = "Dad",
                text = "Pick you up soon",
                isOutgoing = false,
                timestamp = 5000L
            ),
            ChatMessageRecord(
                id = "m2",
                appPackage = "org.thoughtcrime.securesms",
                appName = "Signal",
                senderOrChat = "Mom",
                text = "Okay!",
                isOutgoing = true,
                timestamp = 6000L
            )
        )

        val jsonArray = records.toJsonArray()
        assertEquals(2, jsonArray.length())

        val parsedList = parseChatMessageRecords(jsonArray)
        assertEquals(2, parsedList.size)
        assertEquals("Messages", parsedList[0].appName)
        assertFalse(parsedList[0].isOutgoing)
        assertEquals("Signal", parsedList[1].appName)
        assertTrue(parsedList[1].isOutgoing)

        // Empty list check
        val emptyArray = emptyList<ChatMessageRecord>().toJsonArray()
        assertEquals(0, emptyArray.length())
        assertTrue(parseChatMessageRecords(emptyArray).isEmpty())
    }
}
