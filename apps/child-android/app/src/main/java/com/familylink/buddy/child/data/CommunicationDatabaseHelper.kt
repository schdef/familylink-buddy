package com.familylink.buddy.child.data

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import androidx.annotation.VisibleForTesting
import java.util.concurrent.ConcurrentHashMap

/**
 * Thread-safe SQLite helper managing call and chat communication history in comms_history.db.
 */
class CommunicationDatabaseHelper @VisibleForTesting internal constructor(
    context: Context?,
    private val useInMemory: Boolean = false
) {
    companion object {
        private const val TAG = "CommsDbHelper"
        const val DATABASE_NAME = "comms_history.db"
        const val DATABASE_VERSION = 2

        const val TABLE_CALL_RECORDS = "call_records"
        const val COLUMN_CALL_ID = "id"
        const val COLUMN_CALL_PHONE_NUMBER = "phone_number"
        const val COLUMN_CALL_CONTACT_NAME = "contact_name"
        const val COLUMN_CALL_TYPE = "call_type"
        const val COLUMN_CALL_TIMESTAMP = "timestamp"
        const val COLUMN_CALL_DURATION = "duration_seconds"

        const val TABLE_CHAT_RECORDS = "chat_records"
        const val COLUMN_CHAT_ID = "id"
        const val COLUMN_CHAT_PACKAGE = "app_package"
        const val COLUMN_CHAT_APP_NAME = "app_name"
        const val COLUMN_CHAT_SENDER_OR_CHAT = "sender_or_chat"
        const val COLUMN_CHAT_TEXT = "text"
        const val COLUMN_CHAT_IS_OUTGOING = "is_outgoing"
        const val COLUMN_CHAT_TIMESTAMP = "timestamp"

        const val TABLE_APP_HISTORY = "app_history"
        const val COLUMN_APP_ID = "id"
        const val COLUMN_APP_PACKAGE = "package_name"
        const val COLUMN_APP_LABEL = "app_label"
        const val COLUMN_APP_TIMESTAMP = "timestamp"

        val SQL_CREATE_CALL_TABLE = """
            CREATE TABLE IF NOT EXISTS $TABLE_CALL_RECORDS (
                $COLUMN_CALL_ID TEXT PRIMARY KEY,
                $COLUMN_CALL_PHONE_NUMBER TEXT NOT NULL,
                $COLUMN_CALL_CONTACT_NAME TEXT,
                $COLUMN_CALL_TYPE TEXT NOT NULL,
                $COLUMN_CALL_TIMESTAMP INTEGER NOT NULL,
                $COLUMN_CALL_DURATION INTEGER NOT NULL
            );
        """.trimIndent()

        val SQL_CREATE_CHAT_TABLE = """
            CREATE TABLE IF NOT EXISTS $TABLE_CHAT_RECORDS (
                $COLUMN_CHAT_ID TEXT PRIMARY KEY,
                $COLUMN_CHAT_PACKAGE TEXT NOT NULL,
                $COLUMN_CHAT_APP_NAME TEXT NOT NULL,
                $COLUMN_CHAT_SENDER_OR_CHAT TEXT NOT NULL,
                $COLUMN_CHAT_TEXT TEXT NOT NULL,
                $COLUMN_CHAT_IS_OUTGOING INTEGER NOT NULL,
                $COLUMN_CHAT_TIMESTAMP INTEGER NOT NULL
            );
        """.trimIndent()

        val SQL_CREATE_APP_HISTORY_TABLE = """
            CREATE TABLE IF NOT EXISTS $TABLE_APP_HISTORY (
                $COLUMN_APP_ID TEXT PRIMARY KEY,
                $COLUMN_APP_PACKAGE TEXT NOT NULL,
                $COLUMN_APP_LABEL TEXT NOT NULL,
                $COLUMN_APP_TIMESTAMP INTEGER NOT NULL
            );
        """.trimIndent()

        val SQL_INDEX_CALL_TIMESTAMP = """
            CREATE INDEX IF NOT EXISTS idx_call_records_timestamp 
            ON $TABLE_CALL_RECORDS ($COLUMN_CALL_TIMESTAMP DESC);
        """.trimIndent()

        val SQL_INDEX_CHAT_TIMESTAMP = """
            CREATE INDEX IF NOT EXISTS idx_chat_records_timestamp 
            ON $TABLE_CHAT_RECORDS ($COLUMN_CHAT_TIMESTAMP DESC);
        """.trimIndent()

        val SQL_INDEX_CHAT_PACKAGE_TIMESTAMP = """
            CREATE INDEX IF NOT EXISTS idx_chat_records_pkg_timestamp 
            ON $TABLE_CHAT_RECORDS ($COLUMN_CHAT_PACKAGE, $COLUMN_CHAT_TIMESTAMP DESC);
        """.trimIndent()

        val SQL_INDEX_APP_HISTORY_TIMESTAMP = """
            CREATE INDEX IF NOT EXISTS idx_app_history_timestamp 
            ON $TABLE_APP_HISTORY ($COLUMN_APP_TIMESTAMP DESC);
        """.trimIndent()

        @Volatile
        private var instance: CommunicationDatabaseHelper? = null

        fun getInstance(context: Context): CommunicationDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: CommunicationDatabaseHelper(context.applicationContext, useInMemory = false).also {
                    instance = it
                }
            }
        }

        @VisibleForTesting
        fun createInMemoryForTesting(): CommunicationDatabaseHelper {
            return CommunicationDatabaseHelper(null, useInMemory = true)
        }

        @VisibleForTesting
        fun setInstanceForTesting(helper: CommunicationDatabaseHelper?) {
            synchronized(this) {
                instance = helper
            }
        }
    }

    private class InternalOpenHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(SQL_CREATE_CALL_TABLE)
            db.execSQL(SQL_CREATE_CHAT_TABLE)
            db.execSQL(SQL_CREATE_APP_HISTORY_TABLE)
            db.execSQL(SQL_INDEX_CALL_TIMESTAMP)
            db.execSQL(SQL_INDEX_CHAT_TIMESTAMP)
            db.execSQL(SQL_INDEX_CHAT_PACKAGE_TIMESTAMP)
            db.execSQL(SQL_INDEX_APP_HISTORY_TIMESTAMP)
            Log.i(TAG, "Communication database created with tables and indexes.")
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 2) {
                db.execSQL(SQL_CREATE_APP_HISTORY_TABLE)
                db.execSQL(SQL_INDEX_APP_HISTORY_TIMESTAMP)
            }
        }
    }

    private val openHelper: InternalOpenHelper? = if (!useInMemory && context != null) {
        InternalOpenHelper(context)
    } else {
        null
    }

    // In-memory collections for fast caching / JVM unit test execution
    private val memoryCalls = ConcurrentHashMap<String, CallRecord>()
    private val memoryChats = ConcurrentHashMap<String, ChatMessageRecord>()
    private val memoryAppHistory = ConcurrentHashMap<String, AppOpeningRecord>()
    private val lock = Any()

    /**
     * Inserts or replaces a CallRecord.
     */
    fun insertCall(record: CallRecord): Long {
        synchronized(lock) {
            memoryCalls[record.id] = record

            val helper = openHelper ?: return 1L
            return try {
                val db = helper.writableDatabase
                val cv = ContentValues().apply {
                    put(COLUMN_CALL_ID, record.id)
                    put(COLUMN_CALL_PHONE_NUMBER, record.phoneNumber)
                    put(COLUMN_CALL_CONTACT_NAME, record.contactName)
                    put(COLUMN_CALL_TYPE, record.callType.name)
                    put(COLUMN_CALL_TIMESTAMP, record.timestamp)
                    put(COLUMN_CALL_DURATION, record.durationSeconds)
                }
                db.insertWithOnConflict(TABLE_CALL_RECORDS, null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            } catch (e: Exception) {
                Log.e(TAG, "Error inserting call record: ${e.message}", e)
                -1L
            }
        }
    }

    /**
     * Inserts or replaces a ChatMessageRecord.
     */
    fun insertChatMessage(record: ChatMessageRecord): Long {
        synchronized(lock) {
            memoryChats[record.id] = record

            val helper = openHelper ?: return 1L
            return try {
                val db = helper.writableDatabase
                val cv = ContentValues().apply {
                    put(COLUMN_CHAT_ID, record.id)
                    put(COLUMN_CHAT_PACKAGE, record.appPackage)
                    put(COLUMN_CHAT_APP_NAME, record.appName)
                    put(COLUMN_CHAT_SENDER_OR_CHAT, record.senderOrChat)
                    put(COLUMN_CHAT_TEXT, record.text)
                    put(COLUMN_CHAT_IS_OUTGOING, if (record.isOutgoing) 1 else 0)
                    put(COLUMN_CHAT_TIMESTAMP, record.timestamp)
                }
                db.insertWithOnConflict(TABLE_CHAT_RECORDS, null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            } catch (e: Exception) {
                Log.e(TAG, "Error inserting chat record: ${e.message}", e)
                -1L
            }
        }
    }

    /**
     * Retrieves calls logged since a specific timestamp, ordered by timestamp descending.
     */
    fun getCallsSince(sinceTimestamp: Long, limit: Int = 100): List<CallRecord> {
        val safeLimit = limit.coerceIn(1, 500)
        synchronized(lock) {
            val helper = openHelper
            if (helper == null) {
                return memoryCalls.values
                    .filter { it.timestamp > sinceTimestamp }
                    .sortedByDescending { it.timestamp }
                    .take(safeLimit)
            }

            val result = mutableListOf<CallRecord>()
            var cursor: Cursor? = null
            try {
                val db = helper.readableDatabase
                cursor = db.query(
                    TABLE_CALL_RECORDS,
                    arrayOf(
                        COLUMN_CALL_ID,
                        COLUMN_CALL_PHONE_NUMBER,
                        COLUMN_CALL_CONTACT_NAME,
                        COLUMN_CALL_TYPE,
                        COLUMN_CALL_TIMESTAMP,
                        COLUMN_CALL_DURATION
                    ),
                    "$COLUMN_CALL_TIMESTAMP > ?",
                    arrayOf(sinceTimestamp.toString()),
                    null,
                    null,
                    "$COLUMN_CALL_TIMESTAMP DESC",
                    safeLimit.toString()
                )

                if (cursor != null && cursor.moveToFirst()) {
                    do {
                        val id = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CALL_ID))
                        val phone = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CALL_PHONE_NUMBER))
                        val contact = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CALL_CONTACT_NAME))
                        val typeStr = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CALL_TYPE))
                        val ts = cursor.getLong(cursor.getColumnIndexOrThrow(COLUMN_CALL_TIMESTAMP))
                        val dur = cursor.getLong(cursor.getColumnIndexOrThrow(COLUMN_CALL_DURATION))

                        result.add(
                            CallRecord(
                                id = id,
                                phoneNumber = phone,
                                contactName = contact,
                                callType = CallType.fromString(typeStr),
                                timestamp = ts,
                                durationSeconds = dur
                            )
                        )
                    } while (cursor.moveToNext())
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error querying calls since $sinceTimestamp: ${e.message}", e)
                return memoryCalls.values
                    .filter { it.timestamp > sinceTimestamp }
                    .sortedByDescending { it.timestamp }
                    .take(safeLimit)
            } finally {
                cursor?.close()
            }
            return result
        }
    }

    /**
     * Retrieves chat messages logged since a specific timestamp, optionally filtered by package name.
     */
    fun getChatsSince(sinceTimestamp: Long, packageFilter: String? = null, limit: Int = 200): List<ChatMessageRecord> {
        val safeLimit = limit.coerceIn(1, 500)
        synchronized(lock) {
            val helper = openHelper
            if (helper == null) {
                return memoryChats.values
                    .filter {
                        it.timestamp > sinceTimestamp &&
                                (packageFilter.isNullOrBlank() || it.appPackage == packageFilter)
                    }
                    .sortedByDescending { it.timestamp }
                    .take(safeLimit)
            }

            val result = mutableListOf<ChatMessageRecord>()
            var cursor: Cursor? = null
            try {
                val db = helper.readableDatabase
                val hasFilter = !packageFilter.isNullOrBlank()
                val selection = if (hasFilter) {
                    "$COLUMN_CHAT_TIMESTAMP > ? AND $COLUMN_CHAT_PACKAGE = ?"
                } else {
                    "$COLUMN_CHAT_TIMESTAMP > ?"
                }
                val selectionArgs = if (hasFilter) {
                    arrayOf(sinceTimestamp.toString(), packageFilter)
                } else {
                    arrayOf(sinceTimestamp.toString())
                }

                cursor = db.query(
                    TABLE_CHAT_RECORDS,
                    arrayOf(
                        COLUMN_CHAT_ID,
                        COLUMN_CHAT_PACKAGE,
                        COLUMN_CHAT_APP_NAME,
                        COLUMN_CHAT_SENDER_OR_CHAT,
                        COLUMN_CHAT_TEXT,
                        COLUMN_CHAT_IS_OUTGOING,
                        COLUMN_CHAT_TIMESTAMP
                    ),
                    selection,
                    selectionArgs,
                    null,
                    null,
                    "$COLUMN_CHAT_TIMESTAMP DESC",
                    safeLimit.toString()
                )

                if (cursor != null && cursor.moveToFirst()) {
                    do {
                        val id = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CHAT_ID))
                        val pkg = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CHAT_PACKAGE))
                        val appName = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CHAT_APP_NAME))
                        val sender = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CHAT_SENDER_OR_CHAT))
                        val text = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_CHAT_TEXT))
                        val isOutgoing = cursor.getInt(cursor.getColumnIndexOrThrow(COLUMN_CHAT_IS_OUTGOING)) == 1
                        val ts = cursor.getLong(cursor.getColumnIndexOrThrow(COLUMN_CHAT_TIMESTAMP))

                        result.add(
                            ChatMessageRecord(
                                id = id,
                                appPackage = pkg,
                                appName = appName,
                                senderOrChat = sender,
                                text = text,
                                isOutgoing = isOutgoing,
                                timestamp = ts
                            )
                        )
                    } while (cursor.moveToNext())
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error querying chats: ${e.message}", e)
                return memoryChats.values
                    .filter {
                        it.timestamp > sinceTimestamp &&
                                (packageFilter.isNullOrBlank() || it.appPackage == packageFilter)
                    }
                    .sortedByDescending { it.timestamp }
                    .take(safeLimit)
            } finally {
                cursor?.close()
            }
            return result
        }
    }

    /**
     * Inserts an AppOpeningRecord into app_history.
     */
    fun insertAppOpening(record: AppOpeningRecord): Long {
        synchronized(lock) {
            memoryAppHistory[record.id] = record

            val helper = openHelper ?: return 1L
            return try {
                val db = helper.writableDatabase
                val cv = ContentValues().apply {
                    put(COLUMN_APP_ID, record.id)
                    put(COLUMN_APP_PACKAGE, record.packageName)
                    put(COLUMN_APP_LABEL, record.appLabel)
                    put(COLUMN_APP_TIMESTAMP, record.timestamp)
                }
                db.insertWithOnConflict(TABLE_APP_HISTORY, null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            } catch (e: Exception) {
                Log.e(TAG, "Error inserting app opening record: ${e.message}", e)
                -1L
            }
        }
    }

    /**
     * Convenience method to insert an app opening by package, label, and timestamp.
     */
    fun insertAppOpening(packageName: String, appLabel: String, timestamp: Long): Long {
        val record = AppOpeningRecord(
            id = "app_${timestamp}_${(packageName.hashCode() and 0x7FFFFFFF)}_${java.util.UUID.randomUUID().toString().take(8)}",
            packageName = packageName,
            appLabel = appLabel,
            timestamp = timestamp
        )
        return insertAppOpening(record)
    }

    /**
     * Retrieves app opening records logged since a specific timestamp, ordered by timestamp descending.
     */
    fun getAppHistorySince(sinceTimestamp: Long, limit: Int = 300): List<AppOpeningRecord> {
        val safeLimit = limit.coerceIn(1, 1000)
        synchronized(lock) {
            val helper = openHelper
            if (helper == null) {
                return memoryAppHistory.values
                    .filter { it.timestamp > sinceTimestamp }
                    .sortedByDescending { it.timestamp }
                    .take(safeLimit)
            }

            val result = mutableListOf<AppOpeningRecord>()
            var cursor: Cursor? = null
            try {
                val db = helper.readableDatabase
                cursor = db.query(
                    TABLE_APP_HISTORY,
                    arrayOf(
                        COLUMN_APP_ID,
                        COLUMN_APP_PACKAGE,
                        COLUMN_APP_LABEL,
                        COLUMN_APP_TIMESTAMP
                    ),
                    "$COLUMN_APP_TIMESTAMP > ?",
                    arrayOf(sinceTimestamp.toString()),
                    null,
                    null,
                    "$COLUMN_APP_TIMESTAMP DESC",
                    safeLimit.toString()
                )

                if (cursor != null && cursor.moveToFirst()) {
                    do {
                        val id = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_APP_ID))
                        val pkg = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_APP_PACKAGE))
                        val label = cursor.getString(cursor.getColumnIndexOrThrow(COLUMN_APP_LABEL))
                        val ts = cursor.getLong(cursor.getColumnIndexOrThrow(COLUMN_APP_TIMESTAMP))

                        result.add(
                            AppOpeningRecord(
                                id = id,
                                packageName = pkg,
                                appLabel = label,
                                timestamp = ts
                            )
                        )
                    } while (cursor.moveToNext())
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error querying app history since $sinceTimestamp: ${e.message}", e)
                return memoryAppHistory.values
                    .filter { it.timestamp > sinceTimestamp }
                    .sortedByDescending { it.timestamp }
                    .take(safeLimit)
            } finally {
                cursor?.close()
            }
            return result
        }
    }

    /**
     * Prunes records older than [days] days from calls, chats, and app history.
     * Returns total number of pruned records.
     */
    fun pruneOlderThan(days: Int = 14): Int {
        val safeDays = days.coerceAtLeast(1)
        val cutoffTimestamp = System.currentTimeMillis() - (safeDays.toLong() * 24L * 60L * 60L * 1000L)
        var totalDeleted = 0

        synchronized(lock) {
            val callsToRemove = memoryCalls.filterValues { it.timestamp < cutoffTimestamp }.keys
            callsToRemove.forEach { memoryCalls.remove(it) }
            totalDeleted += callsToRemove.size

            val chatsToRemove = memoryChats.filterValues { it.timestamp < cutoffTimestamp }.keys
            chatsToRemove.forEach { memoryChats.remove(it) }
            totalDeleted += chatsToRemove.size

            val appHistoryToRemove = memoryAppHistory.filterValues { it.timestamp < cutoffTimestamp }.keys
            appHistoryToRemove.forEach { memoryAppHistory.remove(it) }
            totalDeleted += appHistoryToRemove.size

            val helper = openHelper ?: return totalDeleted
            try {
                val db = helper.writableDatabase
                val deletedCalls = db.delete(
                    TABLE_CALL_RECORDS,
                    "$COLUMN_CALL_TIMESTAMP < ?",
                    arrayOf(cutoffTimestamp.toString())
                )
                val deletedChats = db.delete(
                    TABLE_CHAT_RECORDS,
                    "$COLUMN_CHAT_TIMESTAMP < ?",
                    arrayOf(cutoffTimestamp.toString())
                )
                val deletedAppHistory = db.delete(
                    TABLE_APP_HISTORY,
                    "$COLUMN_APP_TIMESTAMP < ?",
                    arrayOf(cutoffTimestamp.toString())
                )
                return deletedCalls + deletedChats + deletedAppHistory
            } catch (e: Exception) {
                Log.e(TAG, "Error pruning records older than $days days: ${e.message}", e)
                return totalDeleted
            }
        }
    }

    /**
     * Clears all communication and app history records from both memory and SQLite storage.
     */
    fun clearAll() {
        synchronized(lock) {
            memoryCalls.clear()
            memoryChats.clear()
            memoryAppHistory.clear()

            val helper = openHelper ?: return
            try {
                val db = helper.writableDatabase
                db.delete(TABLE_CALL_RECORDS, null, null)
                db.delete(TABLE_CHAT_RECORDS, null, null)
                db.delete(TABLE_APP_HISTORY, null, null)
                Log.i(TAG, "All communication records cleared successfully.")
            } catch (e: Exception) {
                Log.e(TAG, "Error clearing communication database: ${e.message}", e)
            }
        }
    }
}
