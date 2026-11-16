package com.familylink.buddy.child.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Call type enum representing phone call states.
 */
enum class CallType {
    INCOMING,
    OUTGOING,
    MISSED,
    REJECTED;

    companion object {
        fun fromString(value: String?): CallType {
            return when (value?.trim()?.uppercase()) {
                "INCOMING" -> INCOMING
                "OUTGOING" -> OUTGOING
                "MISSED" -> MISSED
                "REJECTED" -> REJECTED
                else -> INCOMING
            }
        }

        fun fromCallLogType(type: Int): CallType {
            return when (type) {
                1 -> INCOMING // CallLog.Calls.INCOMING_TYPE
                2 -> OUTGOING // CallLog.Calls.OUTGOING_TYPE
                3 -> MISSED   // CallLog.Calls.MISSED_TYPE
                5 -> REJECTED // CallLog.Calls.REJECTED_TYPE
                6 -> REJECTED // CallLog.Calls.BLOCKED_TYPE
                else -> INCOMING
            }
        }
    }
}

/**
 * Data model for logged phone calls.
 */
data class CallRecord(
    val id: String = UUID.randomUUID().toString(),
    val phoneNumber: String,
    val contactName: String? = null,
    val callType: CallType,
    val timestamp: Long,
    val durationSeconds: Long = 0L
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("id", id)
            put("phoneNumber", phoneNumber)
            if (contactName != null) {
                put("contactName", contactName)
            } else {
                put("contactName", JSONObject.NULL)
            }
            put("callType", callType.name)
            put("timestamp", timestamp)
            put("durationSeconds", durationSeconds)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): CallRecord {
            val contact = if (json.isNull("contactName")) null else json.optString("contactName").takeIf { it.isNotBlank() }
            return CallRecord(
                id = json.optString("id", UUID.randomUUID().toString()),
                phoneNumber = json.optString("phoneNumber", ""),
                contactName = contact,
                callType = CallType.fromString(json.optString("callType")),
                timestamp = json.optLong("timestamp", System.currentTimeMillis()),
                durationSeconds = json.optLong("durationSeconds", 0L)
            )
        }
    }
}

/**
 * Data model for captured chat messages (incoming notifications & outgoing sent messages).
 */
data class ChatMessageRecord(
    val id: String = UUID.randomUUID().toString(),
    val appPackage: String,
    val appName: String,
    val senderOrChat: String,
    val text: String,
    val isOutgoing: Boolean,
    val timestamp: Long
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("id", id)
            put("appPackage", appPackage)
            put("appName", appName)
            put("senderOrChat", senderOrChat)
            put("text", text)
            put("isOutgoing", isOutgoing)
            put("timestamp", timestamp)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): ChatMessageRecord {
            return ChatMessageRecord(
                id = json.optString("id", UUID.randomUUID().toString()),
                appPackage = json.optString("appPackage", ""),
                appName = json.optString("appName", ""),
                senderOrChat = json.optString("senderOrChat", ""),
                text = json.optString("text", ""),
                isOutgoing = json.optBoolean("isOutgoing", false),
                timestamp = json.optLong("timestamp", System.currentTimeMillis())
            )
        }
    }
}

/**
 * JSON serialization helpers for lists of CallRecords.
 */
@JvmName("callRecordsToJsonArray")
fun List<CallRecord>.toJsonArray(): JSONArray {
    val array = JSONArray()
    for (record in this) {
        array.put(record.toJson())
    }
    return array
}

fun parseCallRecords(jsonArray: JSONArray): List<CallRecord> {
    val list = mutableListOf<CallRecord>()
    for (i in 0 until jsonArray.length()) {
        val obj = jsonArray.optJSONObject(i) ?: continue
        list.add(CallRecord.fromJson(obj))
    }
    return list
}

/**
 * JSON serialization helpers for lists of ChatMessageRecords.
 */
@JvmName("chatMessageRecordsToJsonArray")
fun List<ChatMessageRecord>.toJsonArray(): JSONArray {
    val array = JSONArray()
    for (record in this) {
        array.put(record.toJson())
    }
    return array
}

fun parseChatMessageRecords(jsonArray: JSONArray): List<ChatMessageRecord> {
    val list = mutableListOf<ChatMessageRecord>()
    for (i in 0 until jsonArray.length()) {
        val obj = jsonArray.optJSONObject(i) ?: continue
        list.add(ChatMessageRecord.fromJson(obj))
    }
    return list
}

/**
 * Data model for logged app openings in SQLite app history.
 */
data class AppOpeningRecord(
    val id: String = UUID.randomUUID().toString(),
    val packageName: String,
    val appLabel: String,
    val timestamp: Long
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("id", id)
            put("packageName", packageName)
            put("label", appLabel)
            put("timestamp", timestamp)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): AppOpeningRecord {
            return AppOpeningRecord(
                id = json.optString("id", UUID.randomUUID().toString()),
                packageName = json.optString("packageName", ""),
                appLabel = json.optString("label", json.optString("appLabel", "")),
                timestamp = json.optLong("timestamp", System.currentTimeMillis())
            )
        }
    }
}

/**
 * JSON serialization helpers for lists of AppOpeningRecords.
 */
@JvmName("appOpeningRecordsToJsonArray")
fun List<AppOpeningRecord>.toJsonArray(): JSONArray {
    val array = JSONArray()
    for (record in this) {
        array.put(record.toJson())
    }
    return array
}
