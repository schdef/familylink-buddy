package com.familylink.buddy.child.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AppLimitsManager(
    private var currentDateProvider: () -> String = {
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }
) {
    private var appContext: Context? = null
    private var rules = AppRules()
    private val categoryUsageTodaySeconds = mutableMapOf<String, Long>()
    private val bonusMinutes = mutableMapOf<String, Int>()
    private var lastEvaluationDate = currentDateProvider()

    var activePackageName: String? = null
        private set
    var activeCategoryId: String? = null
        private set

    @Synchronized
    fun setContext(context: Context) {
        this.appContext = context.applicationContext
    }

    @Synchronized
    fun getRules(): AppRules = rules

    @Synchronized
    fun getCategoryUsageSeconds(categoryId: String): Long = categoryUsageTodaySeconds[categoryId] ?: 0L

    @Synchronized
    fun getAllCategoryUsageSeconds(): Map<String, Long> = categoryUsageTodaySeconds.toMap()

    @Synchronized
    fun getBonusMinutes(categoryId: String): Int = bonusMinutes[categoryId] ?: 0

    @Synchronized
    fun getAllBonusMinutes(): Map<String, Int> = bonusMinutes.toMap()

    @Synchronized
    fun setCategoryUsageSeconds(categoryId: String, seconds: Long) {
        categoryUsageTodaySeconds[categoryId] = seconds
    }

    @Synchronized
    fun setDateProvider(provider: () -> String) {
        this.currentDateProvider = provider
    }

    @Synchronized
    fun checkMidnightReset(): Boolean {
        val today = currentDateProvider()
        if (today != lastEvaluationDate) {
            categoryUsageTodaySeconds.clear()
            bonusMinutes.clear()
            lastEvaluationDate = today
            return true
        }
        return false
    }

    @Synchronized
    fun updateRules(newRules: AppRules, prefs: SharedPreferences? = null): AppInterceptionResult {
        checkMidnightReset()
        rules = newRules
        // Overwrite or update bonus minutes from rules if provided
        newRules.bonusMinutes.forEach { (catId, minutes) ->
            bonusMinutes[catId] = minutes
        }

        val targetPrefs = prefs ?: appContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        targetPrefs?.let {
            try {
                saveToPreferences(it)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving rules in updateRules", e)
            }
        }

        val pkg = activePackageName
        if (!pkg.isNullOrBlank()) {
            return onPackageChanged(pkg, null)
        }
        return AppInterceptionResult.None
    }

    /**
     * Atomically adds or removes an individual package from the blacklist without
     * overwriting rules concurrently modified by other parent devices.
     */
    @Synchronized
    fun toggleAppBlacklist(packageName: String, isBlocked: Boolean, prefs: SharedPreferences? = null): Set<String> {
        checkMidnightReset()
        val currentBlacklist = rules.blacklistedPackages.toMutableSet()
        if (isBlocked) {
            currentBlacklist.add(packageName)
        } else {
            currentBlacklist.remove(packageName)
        }
        rules = rules.copy(blacklistedPackages = currentBlacklist)

        val targetPrefs = prefs ?: appContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        targetPrefs?.let {
            try {
                saveToPreferences(it)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving rules in toggleAppBlacklist", e)
            }
        }

        if (isBlocked && activePackageName == packageName) {
            onPackageChanged(packageName, null)
        }

        return rules.blacklistedPackages
    }

    @Synchronized
    fun addBonusMinutes(categoryId: String, extraMinutes: Int, prefs: SharedPreferences? = null): AppInterceptionResult {
        checkMidnightReset()
        val current = bonusMinutes[categoryId] ?: 0
        bonusMinutes[categoryId] = current + extraMinutes

        val targetPrefs = prefs ?: appContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        targetPrefs?.let {
            try {
                saveToPreferences(it)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving bonus minutes in addBonusMinutes", e)
            }
        }

        val pkg = activePackageName
        if (!pkg.isNullOrBlank()) {
            return onPackageChanged(pkg, null)
        }
        return AppInterceptionResult.None
    }

    @Synchronized
    fun onPackageChanged(packageName: String, appName: String?): AppInterceptionResult {
        checkMidnightReset()
        activePackageName = packageName
        val displayName = if (!appName.isNullOrBlank()) appName else packageName

        // 1. Blacklist check
        if (rules.blacklistedPackages.contains(packageName)) {
            activeCategoryId = null
            return AppInterceptionResult.BlockedBlacklist(
                packageName = packageName,
                appName = displayName,
                message = "$displayName ist auf diesem Tablet gesperrt"
            )
        }

        // 2. Category match
        val matchingCategory = rules.categories.firstOrNull { it.packages.contains(packageName) }
        if (matchingCategory != null) {
            val usedSeconds = categoryUsageTodaySeconds[matchingCategory.id] ?: 0L
            val bonus = bonusMinutes[matchingCategory.id] ?: 0
            val totalAllowedSeconds = (matchingCategory.dailyMinutes + bonus) * 60L

            if (usedSeconds >= totalAllowedSeconds) {
                activeCategoryId = null
                return AppInterceptionResult.BlockedCategoryLimit(
                    categoryId = matchingCategory.id,
                    categoryName = matchingCategory.name,
                    message = "Zeitlimit für '${matchingCategory.name}' heute aufgebraucht"
                )
            } else {
                activeCategoryId = matchingCategory.id
                return AppInterceptionResult.Allowed(activeCategoryId = matchingCategory.id)
            }
        } else {
            activeCategoryId = null
            return AppInterceptionResult.Allowed(activeCategoryId = null)
        }
    }

    @Synchronized
    fun onSystemOrLauncherActive(packageName: String? = null) {
        checkMidnightReset()
        activePackageName = packageName
        activeCategoryId = null
    }

    @Synchronized
    fun onTick(isScreenInteractive: Boolean): AppInterceptionResult {
        checkMidnightReset()
        if (!isScreenInteractive) {
            return AppInterceptionResult.None
        }
        val catId = activeCategoryId ?: return AppInterceptionResult.None
        val cat = rules.categories.firstOrNull { it.id == catId } ?: return AppInterceptionResult.None

        val currentSeconds = (categoryUsageTodaySeconds[catId] ?: 0L) + 1L
        categoryUsageTodaySeconds[catId] = currentSeconds

        val bonus = bonusMinutes[catId] ?: 0
        val totalAllowedSeconds = (cat.dailyMinutes + bonus) * 60L

        if (currentSeconds >= totalAllowedSeconds) {
            activeCategoryId = null
            return AppInterceptionResult.BlockedCategoryLimit(
                categoryId = cat.id,
                categoryName = cat.name,
                message = "Zeitlimit für '${cat.name}' heute aufgebraucht"
            )
        }

        return AppInterceptionResult.None
    }

    @Synchronized
    fun saveToPreferences(prefs: SharedPreferences) {
        val editor = prefs.edit()
        editor.putString(KEY_RULES_JSON, rules.toJson())
        editor.putString(KEY_LAST_DATE, lastEvaluationDate)

        val usageJson = JSONObject()
        categoryUsageTodaySeconds.forEach { (k, v) -> usageJson.put(k, v) }
        editor.putString(KEY_CATEGORY_USAGE, usageJson.toString())

        val bonusJson = JSONObject()
        bonusMinutes.forEach { (k, v) -> bonusObjPut(bonusJson, k, v) }
        editor.putString(KEY_BONUS_MINUTES, bonusJson.toString())

        editor.apply()
    }

    private fun bonusObjPut(json: JSONObject, key: String, value: Int) {
        try {
            json.put(key, value)
        } catch (e: Exception) {
            Log.e(TAG, "Error adding bonus to JSON", e)
        }
    }

    @Synchronized
    fun loadFromPreferences(prefs: SharedPreferences) {
        val rulesStr = prefs.getString(KEY_RULES_JSON, null)
        if (!rulesStr.isNullOrBlank()) {
            rules = AppRules.fromJson(rulesStr)
        }

        val today = currentDateProvider()
        val savedDate = prefs.getString(KEY_LAST_DATE, null)

        if (savedDate == today) {
            lastEvaluationDate = today
            categoryUsageTodaySeconds.clear()
            val usageStr = prefs.getString(KEY_CATEGORY_USAGE, null)
            if (!usageStr.isNullOrBlank()) {
                try {
                    val obj = JSONObject(usageStr)
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        categoryUsageTodaySeconds[k] = obj.optLong(k, 0L)
                    }
                } catch (ignored: Exception) {}
            }

            bonusMinutes.clear()
            val bonusStr = prefs.getString(KEY_BONUS_MINUTES, null)
            if (!bonusStr.isNullOrBlank()) {
                try {
                    val obj = JSONObject(bonusStr)
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        bonusMinutes[k] = obj.optInt(k, 0)
                    }
                } catch (ignored: Exception) {}
            }
        } else {
            lastEvaluationDate = today
            categoryUsageTodaySeconds.clear()
            bonusMinutes.clear()
            saveToPreferences(prefs)
        }
    }

    companion object {
        private const val TAG = "AppLimitsManager"
        const val PREFS_NAME = "app_limits_prefs"
        private const val KEY_RULES_JSON = "key_rules_json"
        private const val KEY_LAST_DATE = "key_last_date"
        private const val KEY_CATEGORY_USAGE = "key_category_usage"
        private const val KEY_BONUS_MINUTES = "key_bonus_minutes"

        @Volatile
        private var instance: AppLimitsManager? = null

        fun getInstance(context: Context? = null): AppLimitsManager {
            val existing = instance
            if (existing != null) {
                if (context != null) {
                    if (existing.appContext == null) {
                        existing.appContext = context.applicationContext
                    }
                    if (existing.rules.blacklistedPackages.isEmpty() && existing.rules.categories.isEmpty()) {
                        val prefs = context.applicationContext.getSharedPreferences(
                            PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        existing.loadFromPreferences(prefs)
                    }
                }
                return existing
            }

            return synchronized(this) {
                instance ?: AppLimitsManager().also { manager ->
                    if (context != null) {
                        manager.appContext = context.applicationContext
                        val prefs = context.applicationContext.getSharedPreferences(
                            PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        manager.loadFromPreferences(prefs)
                    }
                    instance = manager
                }
            }
        }

        @androidx.annotation.VisibleForTesting
        fun setInstanceForTesting(manager: AppLimitsManager?) {
            synchronized(this) {
                instance = manager
            }
        }
    }
}
