package com.familylink.buddy.child.data

import android.content.Context
import android.provider.Settings
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import java.io.IOException
import java.util.UUID

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "family_time_prefs")

class FamilyTimeRepository(private val context: Context) {

    val familyTimeData: Flow<FamilyTimeData> = context.dataStore.data
        .map { preferences ->
            val remaining = preferences[KEY_REMAINING_MINUTES] ?: 60
            val limit = preferences[KEY_LIMIT_MINUTES] ?: 120
            val lastUpdated = preferences[KEY_LAST_UPDATED] ?: System.currentTimeMillis()
            val usagesString = preferences[KEY_APP_USAGES] ?: ""

            FamilyTimeData(
                totalRemainingMinutes = remaining,
                totalLimitMinutes = limit,
                lastUpdatedMillis = lastUpdated,
                appUsages = deserializeAppUsages(usagesString)
            )
        }

    val volumeState: Flow<VolumeState> = context.dataStore.data
        .map { preferences ->
            VolumeState(
                mediaVolume = preferences[KEY_VOLUME_MEDIA] ?: -1,
                ringtoneVolume = preferences[KEY_VOLUME_RINGTONE] ?: -1,
                alarmVolume = preferences[KEY_VOLUME_ALARM] ?: -1,
                maxMediaVolume = preferences[KEY_VOLUME_MEDIA_MAX] ?: 15,
                maxRingtoneVolume = preferences[KEY_VOLUME_RINGTONE_MAX] ?: 15,
                maxAlarmVolume = preferences[KEY_VOLUME_ALARM_MAX] ?: 15,
                isMuted = preferences[KEY_VOLUME_MUTED] ?: false,
                deviceToken = preferences[KEY_DEVICE_TOKEN] ?: ""
            )
        }

    val timeBankState: Flow<TimeBankState> = context.dataStore.data
        .map { preferences ->
            TimeBankState(
                isEnabled = preferences[KEY_TIME_BANK_ENABLED] ?: false,
                isChildVisible = preferences[KEY_TIME_BANK_CHILD_VISIBLE] ?: false,
                balance = preferences[KEY_TIME_BANK_BALANCE] ?: 0
            )
        }

    val bedtimeSchedule: Flow<BedtimeSchedule> = context.dataStore.data
        .map { preferences ->
            val activeDaysStr = preferences[KEY_BEDTIME_ACTIVE_DAYS] ?: "1,2,3,4,5,6,7"
            val activeDays = if (activeDaysStr.isBlank()) emptyList() else {
                activeDaysStr.split(",").mapNotNull { it.trim().toIntOrNull() }
            }
            BedtimeSchedule(
                isEnabled = preferences[KEY_BEDTIME_ENABLED] ?: false,
                bedtimeHour = preferences[KEY_BEDTIME_HOUR] ?: 20,
                bedtimeMinute = preferences[KEY_BEDTIME_MINUTE] ?: 30,
                wakeupHour = preferences[KEY_WAKEUP_HOUR] ?: 6,
                wakeupMinute = preferences[KEY_WAKEUP_MINUTE] ?: 45,
                activeDays = if (activeDays.isNotEmpty()) activeDays else listOf(1, 2, 3, 4, 5, 6, 7),
                isCurrentlyBlocked = preferences[KEY_BEDTIME_CURRENTLY_BLOCKED] ?: false
            )
        }

    val parentPin: Flow<String?> = context.dataStore.data
        .map { preferences -> preferences[KEY_PARENT_PIN] }

    suspend fun setParentPin(pin: String?) {
        context.dataStore.edit { preferences ->
            if (pin.isNullOrBlank()) {
                preferences.remove(KEY_PARENT_PIN)
            } else {
                require(ParentPinManager.isValidPinFormat(pin)) {
                    "Parent PIN must be exactly 4 digits"
                }
                preferences[KEY_PARENT_PIN] = pin
            }
        }
    }

    suspend fun getParentPin(): String? {
        return context.dataStore.data.first()[KEY_PARENT_PIN]
    }

    fun getParentPinSync(): String? {
        return runBlocking { getParentPin() }
    }

    suspend fun isPinConfigured(): Boolean {
        val pin = getParentPin()
        return !pin.isNullOrBlank() && ParentPinManager.isValidPinFormat(pin)
    }

    fun isPinConfiguredSync(): Boolean {
        return runBlocking { isPinConfigured() }
    }

    fun verifyParentPin(enteredPin: String): Boolean {
        val configured = getParentPinSync()
        return ParentPinManager.verifyPin(enteredPin, configured)
    }

    suspend fun updateBedtimeSchedule(schedule: BedtimeSchedule) {
        context.dataStore.edit { preferences ->
            preferences[KEY_BEDTIME_ENABLED] = schedule.isEnabled
            preferences[KEY_BEDTIME_HOUR] = schedule.bedtimeHour
            preferences[KEY_BEDTIME_MINUTE] = schedule.bedtimeMinute
            preferences[KEY_WAKEUP_HOUR] = schedule.wakeupHour
            preferences[KEY_WAKEUP_MINUTE] = schedule.wakeupMinute
            preferences[KEY_BEDTIME_ACTIVE_DAYS] = schedule.activeDays.joinToString(",")
            preferences[KEY_BEDTIME_CURRENTLY_BLOCKED] = schedule.isCurrentlyBlocked
        }
    }

    suspend fun updateTimeBankState(state: TimeBankState) {
        context.dataStore.edit { preferences ->
            preferences[KEY_TIME_BANK_ENABLED] = state.isEnabled
            preferences[KEY_TIME_BANK_CHILD_VISIBLE] = state.isChildVisible
            preferences[KEY_TIME_BANK_BALANCE] = state.balance
        }
    }

    suspend fun updateFamilyTimeData(data: FamilyTimeData) {
        context.dataStore.edit { preferences ->
            preferences[KEY_REMAINING_MINUTES] = data.totalRemainingMinutes
            preferences[KEY_LIMIT_MINUTES] = data.totalLimitMinutes
            preferences[KEY_LAST_UPDATED] = data.lastUpdatedMillis
            preferences[KEY_APP_USAGES] = serializeAppUsages(data.appUsages)
        }
    }

    suspend fun updateVolumeState(state: VolumeState) {
        context.dataStore.edit { preferences ->
            preferences[KEY_VOLUME_MEDIA] = state.mediaVolume
            preferences[KEY_VOLUME_RINGTONE] = state.ringtoneVolume
            preferences[KEY_VOLUME_ALARM] = state.alarmVolume
            preferences[KEY_VOLUME_MEDIA_MAX] = state.maxMediaVolume
            preferences[KEY_VOLUME_RINGTONE_MAX] = state.maxRingtoneVolume
            preferences[KEY_VOLUME_ALARM_MAX] = state.maxAlarmVolume
            preferences[KEY_VOLUME_MUTED] = state.isMuted
        }
    }

    suspend fun updateDeviceToken(token: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_DEVICE_TOKEN] = token
        }
    }

    val deviceToken: Flow<String> = context.dataStore.data
        .map { preferences -> preferences[KEY_DEVICE_TOKEN] ?: "" }

    suspend fun getOrCreateDeviceToken(): String {
        val current = context.dataStore.data.first()[KEY_DEVICE_TOKEN]
        if (!current.isNullOrBlank()) {
            return current
        }
        val newToken = UUID.randomUUID().toString()
        updateDeviceToken(newToken)
        return newToken
    }

    fun getOrCreateDeviceTokenSync(): String {
        return runBlocking {
            getOrCreateDeviceToken()
        }
    }

    fun getDeviceIdSync(): String {
        val androidId = try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Exception) {
            null
        }
        if (!androidId.isNullOrBlank()) {
            return androidId
        }
        val prefs = context.getSharedPreferences("device_identity", Context.MODE_PRIVATE)
        var cached = prefs.getString("device_id", null)
        if (cached.isNullOrBlank()) {
            cached = UUID.randomUUID().toString().replace("-", "").take(12)
            prefs.edit().putString("device_id", cached).apply()
        }
        return cached
    }

    suspend fun getOrCreateDeviceId(): String {
        val current = context.dataStore.data.first()[KEY_DEVICE_ID]
        if (!current.isNullOrBlank()) {
            return current
        }
        val id = getDeviceIdSync()
        context.dataStore.edit { preferences ->
            preferences[KEY_DEVICE_ID] = id
        }
        return id
    }

    companion object {
        private val KEY_REMAINING_MINUTES = intPreferencesKey("remaining_minutes")
        private val KEY_LIMIT_MINUTES = intPreferencesKey("limit_minutes")
        private val KEY_LAST_UPDATED = longPreferencesKey("last_updated")
        private val KEY_APP_USAGES = stringPreferencesKey("app_usages")
        // Volume state
        private val KEY_VOLUME_MEDIA = intPreferencesKey("volume_media")
        private val KEY_VOLUME_RINGTONE = intPreferencesKey("volume_ringtone")
        private val KEY_VOLUME_ALARM = intPreferencesKey("volume_alarm")
        private val KEY_VOLUME_MEDIA_MAX = intPreferencesKey("volume_media_max")
        private val KEY_VOLUME_RINGTONE_MAX = intPreferencesKey("volume_ringtone_max")
        private val KEY_VOLUME_ALARM_MAX = intPreferencesKey("volume_alarm_max")
        private val KEY_VOLUME_MUTED = booleanPreferencesKey("volume_muted")
        private val KEY_DEVICE_TOKEN = stringPreferencesKey("device_token")
        private val KEY_DEVICE_ID = stringPreferencesKey("device_id")
        private val KEY_TIME_BANK_ENABLED = booleanPreferencesKey("time_bank_enabled")
        private val KEY_TIME_BANK_CHILD_VISIBLE = booleanPreferencesKey("time_bank_child_visible")
        private val KEY_TIME_BANK_BALANCE = intPreferencesKey("time_bank_balance")
        // Bedtime schedule
        private val KEY_BEDTIME_ENABLED = booleanPreferencesKey("bedtime_enabled")
        private val KEY_BEDTIME_HOUR = intPreferencesKey("bedtime_hour")
        private val KEY_BEDTIME_MINUTE = intPreferencesKey("bedtime_minute")
        private val KEY_WAKEUP_HOUR = intPreferencesKey("bedtime_wakeup_hour")
        private val KEY_WAKEUP_MINUTE = intPreferencesKey("bedtime_wakeup_minute")
        private val KEY_BEDTIME_ACTIVE_DAYS = stringPreferencesKey("bedtime_active_days")
        private val KEY_BEDTIME_CURRENTLY_BLOCKED = booleanPreferencesKey("bedtime_currently_blocked")
        private val KEY_PARENT_PIN = stringPreferencesKey("parent_pin")

        fun serializeAppUsages(usages: List<AppUsage>): String {
            val array = org.json.JSONArray()
            usages.forEach { app ->
                val obj = org.json.JSONObject().apply {
                    put("pkg", app.packageName)
                    put("name", app.appName)
                    put("used", app.usedMinutes)
                    put("limit", app.limitMinutes)
                }
                array.put(obj)
            }
            return array.toString()
        }

        fun deserializeAppUsages(serialized: String): List<AppUsage> {
            if (serialized.isEmpty() || serialized == "[]") return emptyList()
            // Legacy CSV format detection
            if (!serialized.startsWith("[")) {
                return deserializeLegacyCsv(serialized)
            }
            return try {
                val array = org.json.JSONArray(serialized)
                (0 until array.length()).map { i ->
                    val obj = array.getJSONObject(i)
                    AppUsage(
                        packageName = obj.optString("pkg", ""),
                        appName = obj.optString("name", ""),
                        usedMinutes = obj.optInt("used", 0),
                        limitMinutes = obj.optInt("limit", 0)
                    )
                }
            } catch (e: Exception) {
                emptyList()
            }
        }

        private fun deserializeLegacyCsv(serialized: String): List<AppUsage> {
            if (serialized.isEmpty()) return emptyList()
            return try {
                serialized.split("|").mapNotNull {
                    val parts = it.split(";")
                    if (parts.size == 4) {
                        AppUsage(
                            packageName = parts[0],
                            appName = parts[1],
                            usedMinutes = parts[2].toIntOrNull() ?: 0,
                            limitMinutes = parts[3].toIntOrNull() ?: 0
                        )
                    } else null
                }
            } catch (e: Exception) {
                emptyList()
            }
        }
    }
}
