package com.familylink.buddy.child.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.io.IOException

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

    suspend fun updateFamilyTimeData(data: FamilyTimeData) {
        context.dataStore.edit { preferences ->
            preferences[KEY_REMAINING_MINUTES] = data.totalRemainingMinutes
            preferences[KEY_LIMIT_MINUTES] = data.totalLimitMinutes
            preferences[KEY_LAST_UPDATED] = data.lastUpdatedMillis
            preferences[KEY_APP_USAGES] = serializeAppUsages(data.appUsages)
        }
    }

    companion object {
        private val KEY_REMAINING_MINUTES = intPreferencesKey("remaining_minutes")
        private val KEY_LIMIT_MINUTES = intPreferencesKey("limit_minutes")
        private val KEY_LAST_UPDATED = longPreferencesKey("last_updated")
        private val KEY_APP_USAGES = stringPreferencesKey("app_usages")

        fun serializeAppUsages(usages: List<AppUsage>): String {
            return usages.joinToString("|") {
                "${it.packageName};${it.appName};${it.usedMinutes};${it.limitMinutes}"
            }
        }

        fun deserializeAppUsages(serialized: String): List<AppUsage> {
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
