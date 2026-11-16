package com.familylink.buddy.child

import com.familylink.buddy.child.data.AppOpeningRecord
import com.familylink.buddy.child.data.CallRecord
import com.familylink.buddy.child.data.CallType
import com.familylink.buddy.child.data.ChatMessageRecord
import com.familylink.buddy.child.data.CommunicationDatabaseHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class CommunicationDatabaseHelperTest {

    private lateinit var dbHelper: CommunicationDatabaseHelper

    @Before
    fun setUp() {
        dbHelper = CommunicationDatabaseHelper.createInMemoryForTesting()
        CommunicationDatabaseHelper.setInstanceForTesting(dbHelper)
    }

    @After
    fun tearDown() {
        dbHelper.clearAll()
        CommunicationDatabaseHelper.setInstanceForTesting(null)
    }

    @Test
    fun testTableAndIndexSchemaDefinitions() {
        assertEquals("comms_history.db", CommunicationDatabaseHelper.DATABASE_NAME)
        assertEquals(2, CommunicationDatabaseHelper.DATABASE_VERSION)

        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CALL_TABLE.contains("call_records"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CALL_TABLE.contains("id TEXT PRIMARY KEY"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CALL_TABLE.contains("phone_number TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CALL_TABLE.contains("call_type TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CALL_TABLE.contains("timestamp INTEGER NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CALL_TABLE.contains("duration_seconds INTEGER NOT NULL"))

        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("chat_records"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("id TEXT PRIMARY KEY"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("app_package TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("sender_or_chat TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("text TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("is_outgoing INTEGER NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_CHAT_TABLE.contains("timestamp INTEGER NOT NULL"))

        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_APP_HISTORY_TABLE.contains("app_history"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_APP_HISTORY_TABLE.contains("id TEXT PRIMARY KEY"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_APP_HISTORY_TABLE.contains("package_name TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_APP_HISTORY_TABLE.contains("app_label TEXT NOT NULL"))
        assertTrue(CommunicationDatabaseHelper.SQL_CREATE_APP_HISTORY_TABLE.contains("timestamp INTEGER NOT NULL"))

        assertTrue(CommunicationDatabaseHelper.SQL_INDEX_CALL_TIMESTAMP.contains("idx_call_records_timestamp"))
        assertTrue(CommunicationDatabaseHelper.SQL_INDEX_CHAT_TIMESTAMP.contains("idx_chat_records_timestamp"))
        assertTrue(CommunicationDatabaseHelper.SQL_INDEX_CHAT_PACKAGE_TIMESTAMP.contains("idx_chat_records_pkg_timestamp"))
        assertTrue(CommunicationDatabaseHelper.SQL_INDEX_APP_HISTORY_TIMESTAMP.contains("idx_app_history_timestamp"))
    }

    @Test
    fun testInsertCallAndGetCallsSince() {
        val now = System.currentTimeMillis()
        val c1 = CallRecord(id = "c1", phoneNumber = "111", contactName = "Mom", callType = CallType.INCOMING, timestamp = now - 3000L, durationSeconds = 30L)
        val c2 = CallRecord(id = "c2", phoneNumber = "222", contactName = "Dad", callType = CallType.OUTGOING, timestamp = now - 2000L, durationSeconds = 45L)
        val c3 = CallRecord(id = "c3", phoneNumber = "333", contactName = null, callType = CallType.MISSED, timestamp = now - 1000L, durationSeconds = 0L)

        dbHelper.insertCall(c1)
        dbHelper.insertCall(c2)
        dbHelper.insertCall(c3)

        // Query all calls since (now - 5000L)
        val allCalls = dbHelper.getCallsSince(now - 5000L)
        assertEquals(3, allCalls.size)
        // Descending order verification
        assertEquals("c3", allCalls[0].id)
        assertEquals("c2", allCalls[1].id)
        assertEquals("c1", allCalls[2].id)

        // Query calls since (now - 2500L)
        val recentCalls = dbHelper.getCallsSince(now - 2500L)
        assertEquals(2, recentCalls.size)
        assertEquals("c3", recentCalls[0].id)
        assertEquals("c2", recentCalls[1].id)

        // Query with limit
        val limitedCalls = dbHelper.getCallsSince(now - 5000L, limit = 1)
        assertEquals(1, limitedCalls.size)
        assertEquals("c3", limitedCalls[0].id)

        // Update / Conflict replace test
        val c2Updated = c2.copy(durationSeconds = 90L)
        dbHelper.insertCall(c2Updated)
        val updatedCalls = dbHelper.getCallsSince(now - 5000L)
        assertEquals(3, updatedCalls.size)
        assertEquals(90L, updatedCalls.first { it.id == "c2" }.durationSeconds)
    }

    @Test
    fun testInsertChatMessageAndGetChatsSince() {
        val now = System.currentTimeMillis()
        val m1 = ChatMessageRecord(
            id = "m1",
            appPackage = "com.whatsapp",
            appName = "WhatsApp",
            senderOrChat = "School Group",
            text = "Homework assignment page 42",
            isOutgoing = false,
            timestamp = now - 4000L
        )
        val m2 = ChatMessageRecord(
            id = "m2",
            appPackage = "com.google.android.apps.messaging",
            appName = "Messages",
            senderOrChat = "Doctor Office",
            text = "Appointment confirmed",
            isOutgoing = false,
            timestamp = now - 3000L
        )
        val m3 = ChatMessageRecord(
            id = "m3",
            appPackage = "com.whatsapp",
            appName = "WhatsApp",
            senderOrChat = "Mom",
            text = "On my way home",
            isOutgoing = true,
            timestamp = now - 2000L
        )
        val m4 = ChatMessageRecord(
            id = "m4",
            appPackage = "org.telegram.messenger",
            appName = "Telegram",
            senderOrChat = "Friend",
            text = "Play soccer?",
            isOutgoing = false,
            timestamp = now - 1000L
        )

        dbHelper.insertChatMessage(m1)
        dbHelper.insertChatMessage(m2)
        dbHelper.insertChatMessage(m3)
        dbHelper.insertChatMessage(m4)

        // Query all since
        val allChats = dbHelper.getChatsSince(now - 5000L)
        assertEquals(4, allChats.size)
        assertEquals("m4", allChats[0].id)
        assertEquals("m3", allChats[1].id)
        assertEquals("m2", allChats[2].id)
        assertEquals("m1", allChats[3].id)

        // Query with package filter "com.whatsapp"
        val whatsappChats = dbHelper.getChatsSince(now - 5000L, packageFilter = "com.whatsapp")
        assertEquals(2, whatsappChats.size)
        assertEquals("m3", whatsappChats[0].id)
        assertEquals("m1", whatsappChats[1].id)

        // Query with package filter "org.telegram.messenger"
        val telegramChats = dbHelper.getChatsSince(now - 5000L, packageFilter = "org.telegram.messenger")
        assertEquals(1, telegramChats.size)
        assertEquals("m4", telegramChats[0].id)

        // Query with limit
        val limited = dbHelper.getChatsSince(now - 5000L, limit = 2)
        assertEquals(2, limited.size)
    }

    @Test
    fun testInsertAppOpeningAndGetAppHistorySince() {
        val now = System.currentTimeMillis()
        dbHelper.insertAppOpening("com.google.android.youtube", "YouTube", now - 4000L)
        dbHelper.insertAppOpening("com.roblox.client", "Roblox", now - 3000L)
        dbHelper.insertAppOpening("com.mojang.minecraftpe", "Minecraft", now - 2000L)

        val history = dbHelper.getAppHistorySince(now - 5000L)
        assertEquals(3, history.size)
        // Descending timestamp order
        assertEquals("com.mojang.minecraftpe", history[0].packageName)
        assertEquals("Minecraft", history[0].appLabel)
        assertEquals("com.roblox.client", history[1].packageName)
        assertEquals("Roblox", history[1].appLabel)
        assertEquals("com.google.android.youtube", history[2].packageName)
        assertEquals("YouTube", history[2].appLabel)

        // Query with limit
        val limited = dbHelper.getAppHistorySince(now - 5000L, limit = 2)
        assertEquals(2, limited.size)
        assertEquals("com.mojang.minecraftpe", limited[0].packageName)
        assertEquals("com.roblox.client", limited[1].packageName)

        // Query since recent timestamp
        val recent = dbHelper.getAppHistorySince(now - 2500L)
        assertEquals(1, recent.size)
        assertEquals("com.mojang.minecraftpe", recent[0].packageName)
    }

    @Test
    fun testPruneOlderThan() {
        val now = System.currentTimeMillis()
        val twentyDaysAgo = now - (20L * 24L * 60L * 60L * 1000L)
        val fiveDaysAgo = now - (5L * 24L * 60L * 60L * 1000L)

        // Insert old and new call
        dbHelper.insertCall(CallRecord("old_call", "111", null, CallType.INCOMING, twentyDaysAgo, 10L))
        dbHelper.insertCall(CallRecord("new_call", "222", null, CallType.OUTGOING, fiveDaysAgo, 20L))

        // Insert old and new chat
        dbHelper.insertChatMessage(ChatMessageRecord("old_chat", "com.whatsapp", "WhatsApp", "A", "Hi", false, twentyDaysAgo))
        dbHelper.insertChatMessage(ChatMessageRecord("new_chat", "com.whatsapp", "WhatsApp", "B", "Hello", true, fiveDaysAgo))

        // Insert old and new app history
        dbHelper.insertAppOpening("com.old.app", "Old App", twentyDaysAgo)
        dbHelper.insertAppOpening("com.new.app", "New App", fiveDaysAgo)

        // Prune older than 14 days
        val prunedCount = dbHelper.pruneOlderThan(days = 14)
        assertEquals(3, prunedCount)

        val remainingCalls = dbHelper.getCallsSince(0L)
        assertEquals(1, remainingCalls.size)
        assertEquals("new_call", remainingCalls[0].id)

        val remainingChats = dbHelper.getChatsSince(0L)
        assertEquals(1, remainingChats.size)
        assertEquals("new_chat", remainingChats[0].id)

        val remainingAppHistory = dbHelper.getAppHistorySince(0L)
        assertEquals(1, remainingAppHistory.size)
        assertEquals("com.new.app", remainingAppHistory[0].packageName)
    }

    @Test
    fun testClearAll() {
        dbHelper.insertCall(CallRecord("c1", "123", null, CallType.INCOMING, 1000L, 5L))
        dbHelper.insertChatMessage(ChatMessageRecord("m1", "pkg", "App", "S", "T", false, 1000L))
        dbHelper.insertAppOpening("com.example.app", "Example", 1000L)

        assertEquals(1, dbHelper.getCallsSince(0L).size)
        assertEquals(1, dbHelper.getChatsSince(0L).size)
        assertEquals(1, dbHelper.getAppHistorySince(0L).size)

        dbHelper.clearAll()

        assertEquals(0, dbHelper.getCallsSince(0L).size)
        assertEquals(0, dbHelper.getChatsSince(0L).size)
        assertEquals(0, dbHelper.getAppHistorySince(0L).size)
    }

    @Test
    fun testThreadSafetyConcurrentInsertions() {
        val threadCount = 8
        val itemsPerThread = 50
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            executor.submit {
                try {
                    for (i in 0 until itemsPerThread) {
                        val id = "t_${t}_$i"
                        val ts = System.currentTimeMillis() + i
                        dbHelper.insertCall(CallRecord(id, "123$i", null, CallType.INCOMING, ts, 10L))
                        dbHelper.insertChatMessage(ChatMessageRecord(id, "com.pkg", "App", "Sender", "Text $i", false, ts))
                        dbHelper.insertAppOpening("com.pkg.$i", "App $i", ts)
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        val completed = latch.await(5, TimeUnit.SECONDS)
        executor.shutdown()
        assertTrue(completed)

        val totalExpected = threadCount * itemsPerThread
        val calls = dbHelper.getCallsSince(0L, limit = 500)
        val chats = dbHelper.getChatsSince(0L, limit = 500)
        val appHistory = dbHelper.getAppHistorySince(0L, limit = 500)

        // Clamped at 500 (safe limit) or exact
        assertTrue(calls.size in totalExpected..500)
        assertTrue(chats.size in totalExpected..500)
        assertTrue(appHistory.size in totalExpected..500)
    }
}
