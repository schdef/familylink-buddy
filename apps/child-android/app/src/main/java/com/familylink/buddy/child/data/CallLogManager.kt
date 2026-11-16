package com.familylink.buddy.child.data

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CallLog
import android.provider.ContactsContract
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Manages reading native call log history and syncing records into CommunicationDatabaseHelper.
 */
object CallLogManager {
    private const val TAG = "CallLogManager"

    fun hasCallLogPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasContactsPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Resolves a contact display name from phone number via ContactsContract.PhoneLookup.
     */
    fun resolveContactName(context: Context, phoneNumber: String): String? {
        if (phoneNumber.isBlank() || !hasContactsPermission(context)) {
            return null
        }
        var contactName: String? = null
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(phoneNumber)
        )
        val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)

        try {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    if (nameIdx >= 0) {
                        contactName = cursor.getString(nameIdx)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed resolving contact name for $phoneNumber: ${e.message}")
        }
        return contactName
    }

    /**
     * Reads call history from CallLog.Calls.CONTENT_URI and stores new entries into
     * CommunicationDatabaseHelper.
     * Returns count of calls synced.
     */
    fun syncCallLogs(context: Context, sinceTimestamp: Long = 0L, limit: Int = 100): Int {
        if (!hasCallLogPermission(context)) {
            Log.d(TAG, "Cannot sync call logs: READ_CALL_LOG permission not granted.")
            return 0
        }

        val safeLimit = limit.coerceIn(1, 500)
        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )

        val selection = "${CallLog.Calls.DATE} > ?"
        val selectionArgs = arrayOf(sinceTimestamp.toString())
        val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT $safeLimit"

        var syncedCount = 0
        val dbHelper = CommunicationDatabaseHelper.getInstance(context)

        try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndex(CallLog.Calls._ID)
                val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)

                while (cursor.moveToNext()) {
                    val rawId = if (idIdx >= 0) cursor.getString(idIdx) else ""
                    val number = if (numIdx >= 0) cursor.getString(numIdx) ?: "Unknown" else "Unknown"
                    var cachedName = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    val type = if (typeIdx >= 0) cursor.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                    val date = if (dateIdx >= 0) cursor.getLong(dateIdx) else System.currentTimeMillis()
                    val duration = if (durIdx >= 0) cursor.getLong(durIdx) else 0L

                    if (cachedName.isNullOrBlank()) {
                        cachedName = resolveContactName(context, number)
                    }

                    val callRecordId = if (rawId.isNotBlank()) "call_$rawId" else "call_${date}_${number.hashCode()}"
                    val callRecord = CallRecord(
                        id = callRecordId,
                        phoneNumber = number,
                        contactName = cachedName,
                        callType = CallType.fromCallLogType(type),
                        timestamp = date,
                        durationSeconds = duration
                    )

                    dbHelper.insertCall(callRecord)
                    syncedCount++
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying system call log: ${e.message}", e)
        }

        return syncedCount
    }
}
