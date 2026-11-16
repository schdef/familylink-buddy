package com.familylink.buddy.child

import com.familylink.buddy.child.data.AppInterceptionResult
import com.familylink.buddy.child.data.AppLimitsManager
import com.familylink.buddy.child.data.AppRules
import com.familylink.buddy.child.data.CategoryConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLimitsLogicTest {

    @Test
    fun testBlacklistMatching() {
        val manager = AppLimitsManager()
        val rules = AppRules(
            blacklistedPackages = setOf(
                "com.google.android.apps.chromecast.app",
                "com.android.settings"
            )
        )
        manager.updateRules(rules)

        // 1. Blacklisted app with custom name
        val resultGoogleHome = manager.onPackageChanged("com.google.android.apps.chromecast.app", "Google Home")
        assertTrue(resultGoogleHome is AppInterceptionResult.BlockedBlacklist)
        val blockedGoogleHome = resultGoogleHome as AppInterceptionResult.BlockedBlacklist
        assertEquals("com.google.android.apps.chromecast.app", blockedGoogleHome.packageName)
        assertEquals("Google Home", blockedGoogleHome.appName)
        assertEquals("Google Home ist auf diesem Tablet gesperrt", blockedGoogleHome.message)
        assertNull(manager.activeCategoryId)

        // 2. Blacklisted app with fallback package name
        val resultSettings = manager.onPackageChanged("com.android.settings", null)
        assertTrue(resultSettings is AppInterceptionResult.BlockedBlacklist)
        val blockedSettings = resultSettings as AppInterceptionResult.BlockedBlacklist
        assertEquals("com.android.settings ist auf diesem Tablet gesperrt", blockedSettings.message)
        assertNull(manager.activeCategoryId)

        // 3. Allowed app
        val resultAllowed = manager.onPackageChanged("com.example.calculator", "Taschenrechner")
        assertTrue(resultAllowed is AppInterceptionResult.Allowed)
        assertNull(manager.activeCategoryId)
    }

    @Test
    fun testCategoryUsageAccumulation() {
        val manager = AppLimitsManager()
        val gameCategory = CategoryConfig(
            id = "games",
            name = "Spiele",
            dailyMinutes = 30,
            packages = setOf("com.roblox.client", "com.supercell.brawlstars")
        )
        val rules = AppRules(categories = listOf(gameCategory))
        manager.updateRules(rules)

        // Open Roblox
        val result = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(result is AppInterceptionResult.Allowed)
        assertEquals("games", (result as AppInterceptionResult.Allowed).activeCategoryId)
        assertEquals("games", manager.activeCategoryId)

        // Ticking when screen is interactive
        for (i in 1..10) {
            val tickResult = manager.onTick(isScreenInteractive = true)
            assertTrue(tickResult is AppInterceptionResult.None)
        }
        assertEquals(10L, manager.getCategoryUsageSeconds("games"))

        // Ticking when screen is off/non-interactive should NOT accumulate
        for (i in 1..5) {
            val tickResult = manager.onTick(isScreenInteractive = false)
            assertTrue(tickResult is AppInterceptionResult.None)
        }
        assertEquals(10L, manager.getCategoryUsageSeconds("games"))

        // Launcher active should pause category accumulation
        manager.onSystemOrLauncherActive("com.google.android.apps.nexuslauncher")
        assertNull(manager.activeCategoryId)

        for (i in 1..5) {
            manager.onTick(isScreenInteractive = true)
        }
        assertEquals(10L, manager.getCategoryUsageSeconds("games"))

        // Switch to Brawl Stars in same category -> resumes and shares pool
        val resultBrawl = manager.onPackageChanged("com.supercell.brawlstars", "Brawl Stars")
        assertTrue(resultBrawl is AppInterceptionResult.Allowed)
        assertEquals("games", manager.activeCategoryId)

        for (i in 1..15) {
            manager.onTick(isScreenInteractive = true)
        }
        assertEquals(25L, manager.getCategoryUsageSeconds("games"))
    }

    @Test
    fun testLimitEnforcementWhenUsageReachesLimit() {
        val manager = AppLimitsManager()
        val gameCategory = CategoryConfig(
            id = "games",
            name = "Spiele",
            dailyMinutes = 2, // 120 seconds
            packages = setOf("com.roblox.client")
        )
        manager.updateRules(AppRules(categories = listOf(gameCategory)))

        val openResult = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(openResult is AppInterceptionResult.Allowed)

        // Tick 119 seconds -> should remain allowed
        for (i in 1..119) {
            val tickResult = manager.onTick(isScreenInteractive = true)
            assertTrue(tickResult is AppInterceptionResult.None)
        }
        assertEquals(119L, manager.getCategoryUsageSeconds("games"))

        // 120th tick -> reached limit!
        val reachedResult = manager.onTick(isScreenInteractive = true)
        assertTrue(reachedResult is AppInterceptionResult.BlockedCategoryLimit)
        val blockedLimit = reachedResult as AppInterceptionResult.BlockedCategoryLimit
        assertEquals("games", blockedLimit.categoryId)
        assertEquals("Spiele", blockedLimit.categoryName)
        assertEquals("Zeitlimit für 'Spiele' heute aufgebraucht", blockedLimit.message)
        assertNull(manager.activeCategoryId)

        // Subsequent attempt to open Roblox immediately returns BlockedCategoryLimit
        val reattemptResult = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(reattemptResult is AppInterceptionResult.BlockedCategoryLimit)
        val blockedReattempt = reattemptResult as AppInterceptionResult.BlockedCategoryLimit
        assertEquals("Zeitlimit für 'Spiele' heute aufgebraucht", blockedReattempt.message)
        assertNull(manager.activeCategoryId)
    }

    @Test
    fun testBonusMinutesExtension() {
        val manager = AppLimitsManager()
        val gameCategory = CategoryConfig(
            id = "games",
            name = "Spiele",
            dailyMinutes = 2, // 120 seconds
            packages = setOf("com.roblox.client")
        )
        manager.updateRules(AppRules(categories = listOf(gameCategory)))

        // Pre-fill usage to limit (120 seconds)
        manager.setCategoryUsageSeconds("games", 120L)

        // Attempting to open is blocked
        val blockedAttempt = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(blockedAttempt is AppInterceptionResult.BlockedCategoryLimit)

        // Parent grants 15 bonus minutes
        manager.addBonusMinutes("games", 15)
        assertEquals(15, manager.getBonusMinutes("games"))

        // Now total allowed is (2 + 15) * 60 = 1020 seconds
        val allowedAttempt = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(allowedAttempt is AppInterceptionResult.Allowed)
        assertEquals("games", manager.activeCategoryId)

        // Tick 899 more seconds (120 + 899 = 1019s)
        for (i in 1..899) {
            val tickResult = manager.onTick(isScreenInteractive = true)
            assertTrue(tickResult is AppInterceptionResult.None)
        }
        assertEquals(1019L, manager.getCategoryUsageSeconds("games"))

        // Next tick reaches 1020s -> limit reached again
        val finalBlock = manager.onTick(isScreenInteractive = true)
        assertTrue(finalBlock is AppInterceptionResult.BlockedCategoryLimit)
        assertEquals("Zeitlimit für 'Spiele' heute aufgebraucht", (finalBlock as AppInterceptionResult.BlockedCategoryLimit).message)
    }

    @Test
    fun testMidnightDateChangeReset() {
        var testDate = "2026-11-04"
        val manager = AppLimitsManager(currentDateProvider = { testDate })

        val gameCategory = CategoryConfig(
            id = "games",
            name = "Spiele",
            dailyMinutes = 5,
            packages = setOf("com.roblox.client")
        )
        manager.updateRules(AppRules(categories = listOf(gameCategory)))

        // Day 1: usage and bonus accumulated
        manager.setCategoryUsageSeconds("games", 300L) // 5 min exhausted
        manager.addBonusMinutes("games", 10)
        assertEquals(300L, manager.getCategoryUsageSeconds("games"))
        assertEquals(10, manager.getBonusMinutes("games"))

        // Same day reset check returns false
        assertFalse(manager.checkMidnightReset())

        // Rollover to next day at midnight
        testDate = "2026-11-05"
        val resetOccurred = manager.checkMidnightReset()
        assertTrue(resetOccurred)

        // Usage and bonus must be completely reset
        assertEquals(0L, manager.getCategoryUsageSeconds("games"))
        assertEquals(0, manager.getBonusMinutes("games"))

        // Opening Roblox on the new day is allowed from fresh 0 usage
        val resultNextDay = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(resultNextDay is AppInterceptionResult.Allowed)
        assertEquals("games", manager.activeCategoryId)
    }

    @Test
    fun testAppRulesSerializationAndDeserialization() {
        val original = AppRules(
            blacklistedPackages = setOf("com.google.android.apps.chromecast.app", "com.android.settings"),
            categories = listOf(
                CategoryConfig(
                    id = "games",
                    name = "Spiele",
                    dailyMinutes = 45,
                    packages = setOf("com.roblox.client", "com.supercell.brawlstars"),
                    icon = "sports_esports"
                ),
                CategoryConfig(
                    id = "streaming",
                    name = "Video",
                    dailyMinutes = 30,
                    packages = setOf("com.google.android.youtube"),
                    icon = "play_circle"
                )
            ),
            bonusMinutes = mapOf("games" to 15, "streaming" to 0)
        )

        // 1. Map roundtrip
        val map = original.toMap()
        val deserializedFromMap = AppRules.fromMap(map)
        assertEquals(original.blacklistedPackages, deserializedFromMap.blacklistedPackages)
        assertEquals(original.categories.size, deserializedFromMap.categories.size)
        assertEquals(original.categories[0].name, deserializedFromMap.categories[0].name)
        assertEquals(original.categories[0].dailyMinutes, deserializedFromMap.categories[0].dailyMinutes)
        assertEquals(original.bonusMinutes, deserializedFromMap.bonusMinutes)

        // 2. JSON roundtrip
        val jsonStr = original.toJson()
        val deserializedFromJson = AppRules.fromJson(jsonStr)
        assertEquals(original.blacklistedPackages, deserializedFromJson.blacklistedPackages)
        assertEquals(original.categories.size, deserializedFromJson.categories.size)
        assertEquals(original.categories[1].packages, deserializedFromJson.categories[1].packages)
        assertEquals(original.bonusMinutes, deserializedFromJson.bonusMinutes)

        // 3. Test dailyLimitMinutes alias
        val mapWithAlias: Map<String, Any?> = mapOf(
            "categories" to listOf(
                mapOf(
                    "id" to "learning",
                    "name" to "Lernen",
                    "dailyLimitMinutes" to 60,
                    "packages" to listOf("de.anton.app")
                )
            )
        )
        val rulesFromAlias = AppRules.fromMap(mapWithAlias)
        assertEquals(60, rulesFromAlias.categories[0].dailyMinutes)
    }

    @Test
    fun testAppNotInAnyCategoryDoesNotAccumulateUsage() {
        val manager = AppLimitsManager()
        val gameCategory = CategoryConfig(
            id = "games",
            name = "Spiele",
            dailyMinutes = 20,
            packages = setOf("com.roblox.client")
        )
        manager.updateRules(AppRules(categories = listOf(gameCategory)))

        // Open an educational app not in any category
        val result = manager.onPackageChanged("de.anton.app", "Anton")
        assertTrue(result is AppInterceptionResult.Allowed)
        assertNull((result as AppInterceptionResult.Allowed).activeCategoryId)
        assertNull(manager.activeCategoryId)

        // Ticking should not increment games
        for (i in 1..20) {
            val tickResult = manager.onTick(isScreenInteractive = true)
            assertTrue(tickResult is AppInterceptionResult.None)
        }
        assertEquals(0L, manager.getCategoryUsageSeconds("games"))
    }

    @Test
    fun testMultipleCategoriesIndependentLimits() {
        val manager = AppLimitsManager()
        val rules = AppRules(
            categories = listOf(
                CategoryConfig(
                    id = "games",
                    name = "Spiele",
                    dailyMinutes = 1, // 60s
                    packages = setOf("com.roblox.client")
                ),
                CategoryConfig(
                    id = "video",
                    name = "Videos",
                    dailyMinutes = 2, // 120s
                    packages = setOf("com.google.android.youtube")
                )
            )
        )
        manager.updateRules(rules)

        // Exhaust games limit (60s)
        manager.onPackageChanged("com.roblox.client", "Roblox")
        for (i in 1..60) {
            manager.onTick(isScreenInteractive = true)
        }
        assertEquals(60L, manager.getCategoryUsageSeconds("games"))
        assertEquals(0L, manager.getCategoryUsageSeconds("video"))

        // Roblox is now blocked
        val robloxAttempt = manager.onPackageChanged("com.roblox.client", "Roblox")
        assertTrue(robloxAttempt is AppInterceptionResult.BlockedCategoryLimit)

        // But YouTube in "video" category remains allowed!
        val ytAttempt = manager.onPackageChanged("com.google.android.youtube", "YouTube")
        assertTrue(ytAttempt is AppInterceptionResult.Allowed)
        assertEquals("video", manager.activeCategoryId)

        // Video can accumulate independently
        for (i in 1..30) {
            manager.onTick(isScreenInteractive = true)
        }
        assertEquals(30L, manager.getCategoryUsageSeconds("video"))
        assertEquals(60L, manager.getCategoryUsageSeconds("games"))
    }

    @Test
    fun testGoogleSearchBoxBlacklistInterception() {
        val manager = AppLimitsManager()
        val rules = AppRules(
            blacklistedPackages = setOf(
                com.familylink.buddy.child.data.InstalledAppsManager.GOOGLE_SEARCH_PACKAGE
            )
        )
        manager.updateRules(rules)

        val result = manager.onPackageChanged(
            com.familylink.buddy.child.data.InstalledAppsManager.GOOGLE_SEARCH_PACKAGE,
            "Google"
        )
        assertTrue(result is AppInterceptionResult.BlockedBlacklist)
        val blocked = result as AppInterceptionResult.BlockedBlacklist
        assertEquals(com.familylink.buddy.child.data.InstalledAppsManager.GOOGLE_SEARCH_PACKAGE, blocked.packageName)
        assertEquals("Google", blocked.appName)
        assertEquals("Google ist auf diesem Tablet gesperrt", blocked.message)
    }

    @Test
    fun testExcludedAllowedAppsFiltering() {
        val ownPkg = "com.familylink.buddy.child"

        // Allowed / essential apps must be excluded from blockable list
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.spotify.music", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.familylink.buddy.child", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.android.settings", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.google.android.settings", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.android.dialer", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.google.android.dialer", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.samsung.android.dialer", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.android.phone", ownPackage = ownPkg))
        assertTrue(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.android.systemui", ownPackage = ownPkg))

        // Standard games/apps and Google Search must NOT be excluded (they are blockable)
        assertFalse(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.roblox.client", ownPackage = ownPkg))
        assertFalse(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.mojang.minecraftpe", ownPackage = ownPkg))
        assertFalse(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.google.android.youtube", ownPackage = ownPkg))
        assertFalse(com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(null, "com.google.android.googlequicksearchbox", ownPackage = ownPkg))
    }

    @Test
    fun testRulesPersistenceAndImmediateSave() {
        val fakePrefs = FakeSharedPreferences()
        val manager = AppLimitsManager()

        val rules = AppRules(
            blacklistedPackages = setOf("com.tiktok.android"),
            bonusMinutes = mapOf("cat_games" to 15)
        )
        // updateRules saves to prefs immediately
        manager.updateRules(rules, fakePrefs)

        // Verify stored in prefs
        assertTrue(fakePrefs.map.containsKey("key_rules_json"))

        // New manager instance loading from prefs
        val newManager = AppLimitsManager()
        newManager.loadFromPreferences(fakePrefs)
        assertEquals(setOf("com.tiktok.android"), newManager.getRules().blacklistedPackages)
        assertEquals(15, newManager.getBonusMinutes("cat_games"))
    }

    @Test
    fun testToggleAppBlacklistAtomicAddAndRemove() {
        val fakePrefs = FakeSharedPreferences()
        val manager = AppLimitsManager()
        manager.updateRules(AppRules(blacklistedPackages = setOf("com.android.settings")), fakePrefs)

        // 1. Atomic block of Roblox
        val updated1 = manager.toggleAppBlacklist("com.roblox.client", isBlocked = true, prefs = fakePrefs)
        assertTrue(updated1.contains("com.roblox.client"))
        assertTrue(updated1.contains("com.android.settings"))
        assertEquals(setOf("com.android.settings", "com.roblox.client"), manager.getRules().blacklistedPackages)

        // Verify saved to preferences
        val reloadedManager = AppLimitsManager()
        reloadedManager.loadFromPreferences(fakePrefs)
        assertTrue(reloadedManager.getRules().blacklistedPackages.contains("com.roblox.client"))

        // 2. Atomic unblock of Roblox
        val updated2 = manager.toggleAppBlacklist("com.roblox.client", isBlocked = false, prefs = fakePrefs)
        assertFalse(updated2.contains("com.roblox.client"))
        assertTrue(updated2.contains("com.android.settings"))
        assertEquals(setOf("com.android.settings"), manager.getRules().blacklistedPackages)
    }

    @Test
    fun testMultiParentParallelAppBlockingWithoutOverwrites() {
        val fakePrefs = FakeSharedPreferences()
        val manager = AppLimitsManager()
        manager.updateRules(AppRules(), fakePrefs)

        // Parent 1 blocks Roblox
        val parent1Result = manager.toggleAppBlacklist("com.roblox.client", isBlocked = true, prefs = fakePrefs)
        assertEquals(setOf("com.roblox.client"), parent1Result)

        // Parent 2 concurrently blocks TikTok
        val parent2Result = manager.toggleAppBlacklist("com.zhiliaoapp.musically", isBlocked = true, prefs = fakePrefs)
        assertEquals(setOf("com.roblox.client", "com.zhiliaoapp.musically"), parent2Result)

        // Both blocked packages persist safely
        val currentRules = manager.getRules().blacklistedPackages
        assertTrue(currentRules.contains("com.roblox.client"))
        assertTrue(currentRules.contains("com.zhiliaoapp.musically"))

        // Parent 1 unblocks Roblox -> TikTok MUST still remain blocked
        val parent1UnblockResult = manager.toggleAppBlacklist("com.roblox.client", isBlocked = false, prefs = fakePrefs)
        assertFalse(parent1UnblockResult.contains("com.roblox.client"))
        assertTrue(parent1UnblockResult.contains("com.zhiliaoapp.musically"))
        assertEquals(setOf("com.zhiliaoapp.musically"), manager.getRules().blacklistedPackages)
    }

    @Test
    fun testToggleAppBlacklistInterceptsActiveApp() {
        val manager = AppLimitsManager()
        manager.updateRules(AppRules())

        // Child is currently playing Brawl Stars
        val openResult = manager.onPackageChanged("com.supercell.brawlstars", "Brawl Stars")
        assertTrue(openResult is AppInterceptionResult.Allowed)
        assertEquals("com.supercell.brawlstars", manager.activePackageName)

        // Parent instantly blocks Brawl Stars
        manager.toggleAppBlacklist("com.supercell.brawlstars", isBlocked = true)

        // Immediate subsequent evaluation must block it
        val blockedResult = manager.onPackageChanged("com.supercell.brawlstars", "Brawl Stars")
        assertTrue(blockedResult is AppInterceptionResult.BlockedBlacklist)
        val blockedBlacklist = blockedResult as AppInterceptionResult.BlockedBlacklist
        assertEquals("com.supercell.brawlstars", blockedBlacklist.packageName)
    }

    private class FakeSharedPreferences : android.content.SharedPreferences {
        val map = mutableMapOf<String, Any?>()

        override fun getAll(): MutableMap<String, *> = map
        override fun getString(key: String?, defValue: String?): String? = (map[key] as? String) ?: defValue
        @Suppress("UNCHECKED_CAST")
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = (map[key] as? MutableSet<String>) ?: defValues
        override fun getInt(key: String?, defValue: Int): Int = (map[key] as? Int) ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = (map[key] as? Long) ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = (map[key] as? Float) ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = (map[key] as? Boolean) ?: defValue
        override fun contains(key: String?): Boolean = map.containsKey(key)
        override fun edit(): android.content.SharedPreferences.Editor = FakeEditor(this)
        override fun registerOnSharedPreferenceChangeListener(listener: android.content.SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: android.content.SharedPreferences.OnSharedPreferenceChangeListener?) {}

        class FakeEditor(private val prefs: FakeSharedPreferences) : android.content.SharedPreferences.Editor {
            private val temp = mutableMapOf<String, Any?>()
            override fun putString(key: String?, value: String?) = apply { temp[key ?: ""] = value }
            override fun putStringSet(key: String?, values: MutableSet<String>?) = apply { temp[key ?: ""] = values }
            override fun putInt(key: String?, value: Int) = apply { temp[key ?: ""] = value }
            override fun putLong(key: String?, value: Long) = apply { temp[key ?: ""] = value }
            override fun putFloat(key: String?, value: Float) = apply { temp[key ?: ""] = value }
            override fun putBoolean(key: String?, value: Boolean) = apply { temp[key ?: ""] = value }
            override fun remove(key: String?) = apply { temp.remove(key ?: "") }
            override fun clear() = apply { temp.clear() }
            override fun commit(): Boolean { prefs.map.putAll(temp); return true }
            override fun apply() { prefs.map.putAll(temp) }
        }
    }
}
