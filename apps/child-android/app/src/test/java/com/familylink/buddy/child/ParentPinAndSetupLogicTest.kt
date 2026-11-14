package com.familylink.buddy.child

import com.familylink.buddy.child.data.AntiTamperDetector
import com.familylink.buddy.child.data.ParentPinManager
import com.familylink.buddy.child.data.SetupStateDetector
import com.familylink.buddy.child.data.SetupWizardState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ParentPinAndSetupLogicTest {

    // -------------------------------------------------------------
    // 1. PIN Format Tests
    // -------------------------------------------------------------

    @Test
    fun testValidPinFormats() {
        assertTrue(ParentPinManager.isValidPinFormat("1234"))
        assertTrue(ParentPinManager.isValidPinFormat("0000"))
        assertTrue(ParentPinManager.isValidPinFormat("9999"))
        assertTrue(ParentPinManager.isValidPinFormat("5821"))
    }

    @Test
    fun testInvalidPinFormats() {
        assertFalse(ParentPinManager.isValidPinFormat(null))
        assertFalse(ParentPinManager.isValidPinFormat(""))
        assertFalse(ParentPinManager.isValidPinFormat("1"))
        assertFalse(ParentPinManager.isValidPinFormat("12"))
        assertFalse(ParentPinManager.isValidPinFormat("123")) // too short
        assertFalse(ParentPinManager.isValidPinFormat("12345")) // too long
        assertFalse(ParentPinManager.isValidPinFormat("123456"))
        assertFalse(ParentPinManager.isValidPinFormat("12a4")) // non-numeric
        assertFalse(ParentPinManager.isValidPinFormat(" 123")) // space
        assertFalse(ParentPinManager.isValidPinFormat("12-4"))
        assertFalse(ParentPinManager.isValidPinFormat("abcd"))
    }

    // -------------------------------------------------------------
    // 2. PIN Verification Tests
    // -------------------------------------------------------------

    @Test
    fun testVerifyPinWhenConfigured() {
        val configuredPin = "4321"

        assertTrue(ParentPinManager.verifyPin("4321", configuredPin))
        assertFalse(ParentPinManager.verifyPin("1234", configuredPin))
        assertFalse(ParentPinManager.verifyPin("0000", configuredPin))
        assertFalse(ParentPinManager.verifyPin("", configuredPin))
    }

    @Test
    fun testVerifyPinWhenNotConfigured() {
        // If parent has not set a PIN yet, access is unrestricted
        assertTrue(ParentPinManager.verifyPin("1234", null))
        assertTrue(ParentPinManager.verifyPin("", null))
        assertTrue(ParentPinManager.verifyPin("9999", ""))
        assertTrue(ParentPinManager.verifyPin("any", "   "))
    }

    // -------------------------------------------------------------
    // 3. Anti-Tamper Settings Package Detection
    // -------------------------------------------------------------

    @Test
    fun testIsSettingsAppDetection() {
        assertTrue(AntiTamperDetector.isSettingsApp("com.android.settings"))
        assertTrue(AntiTamperDetector.isSettingsApp("com.google.android.settings"))
        assertTrue(AntiTamperDetector.isSettingsApp("com.google.android.settings.intelligence"))
        assertTrue(AntiTamperDetector.isSettingsApp("com.samsung.android.app.telephonyui"))
        assertTrue(AntiTamperDetector.isSettingsApp("com.miui.securitycenter"))
        assertTrue(AntiTamperDetector.isSettingsApp("custom.oem.settings"))

        assertFalse(AntiTamperDetector.isSettingsApp("com.familylink.buddy.child"))
        assertFalse(AntiTamperDetector.isSettingsApp("com.google.android.youtube"))
        assertFalse(AntiTamperDetector.isSettingsApp("com.android.chrome"))
        assertFalse(AntiTamperDetector.isSettingsApp(null))
        assertFalse(AntiTamperDetector.isSettingsApp(""))
    }

    // -------------------------------------------------------------
    // 4. Anti-Tamper Tamper Attempt Detection
    // -------------------------------------------------------------

    @Test
    fun testAccessibilityClassTamperAttempt() {
        val settingsPkg = "com.android.settings"

        assertTrue(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = settingsPkg,
                className = "com.android.settings.accessibility.AccessibilitySettings"
            )
        )

        assertTrue(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = settingsPkg,
                className = "com.android.settings.accessibility.ToggleAccessibilityServicePreferenceFragment"
            )
        )
    }

    @Test
    fun testAccessibilityTextTamperAttempt() {
        val settingsPkg = "com.android.settings"

        assertTrue(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = settingsPkg,
                className = "com.android.settings.SubSettings",
                windowTexts = listOf("Bedienungshilfen", "FamilyLink Buddy", "Aktiviert")
            )
        )

        assertTrue(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = settingsPkg,
                className = "com.android.settings.applications.InstalledAppDetails",
                windowTexts = listOf("FamilyLink Buddy", "Deinstallieren", "Stoppen erzwingen")
            )
        )
    }

    @Test
    fun testHarmlessSettingsAllowed() {
        val settingsPkg = "com.android.settings"

        // Harmless settings (display, sound, bluetooth) should not be treated as accessibility tamper
        assertFalse(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = settingsPkg,
                className = "com.android.settings.DisplaySettings",
                windowTexts = listOf("Display", "Helligkeit", "Dark Mode", "Schriftgröße")
            )
        )

        assertFalse(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = settingsPkg,
                className = "com.android.settings.SoundSettings",
                windowTexts = listOf("Töne", "Medienlautstärke", "Klingelton")
            )
        )
    }

    @Test
    fun testNonSettingsAppNeverTamper() {
        assertFalse(
            AntiTamperDetector.isAccessibilityOrSettingsTamperAttempt(
                packageName = "com.google.android.youtube",
                className = "com.google.android.apps.youtube.app.WatchWhileActivity",
                windowTexts = listOf("Accessibility", "Bedienungshilfe")
            )
        )
    }

    // -------------------------------------------------------------
    // 5. Anti-Tamper Protection Enforcement
    // -------------------------------------------------------------

    @Test
    fun testShouldEnforceTamperProtection() {
        val settingsPkg = "com.android.settings"
        val a11yClass = "com.android.settings.accessibility.AccessibilitySettings"

        // Case A: Child tries to open accessibility settings with PIN configured and locked -> BLOCK!
        assertTrue(
            AntiTamperDetector.shouldEnforceTamperProtection(
                packageName = settingsPkg,
                className = a11yClass,
                isPinConfigured = true,
                isParentUnlocked = false
            )
        )

        // Case B: Parent unlocked anti-tamper via PIN -> ALLOW
        assertFalse(
            AntiTamperDetector.shouldEnforceTamperProtection(
                packageName = settingsPkg,
                className = a11yClass,
                isPinConfigured = true,
                isParentUnlocked = true
            )
        )

        // Case C: PIN is not configured yet (initial setup) -> ALLOW
        assertFalse(
            AntiTamperDetector.shouldEnforceTamperProtection(
                packageName = settingsPkg,
                className = a11yClass,
                isPinConfigured = false,
                isParentUnlocked = false
            )
        )

        // Case D: Harmless settings with PIN configured -> ALLOW
        assertFalse(
            AntiTamperDetector.shouldEnforceTamperProtection(
                packageName = settingsPkg,
                className = "com.android.settings.DisplaySettings",
                isPinConfigured = true,
                isParentUnlocked = false
            )
        )
    }

    // -------------------------------------------------------------
    // 6. Setup State & Progress Calculation Tests
    // -------------------------------------------------------------

    @Test
    fun testSetupProgressPercentage() {
        assertEquals(0, SetupStateDetector.calculateProgressPercentage(0, 4))
        assertEquals(25, SetupStateDetector.calculateProgressPercentage(1, 4))
        assertEquals(50, SetupStateDetector.calculateProgressPercentage(2, 4))
        assertEquals(75, SetupStateDetector.calculateProgressPercentage(3, 4))
        assertEquals(100, SetupStateDetector.calculateProgressPercentage(4, 4))

        // 5-step progress (including Camera permission)
        assertEquals(0, SetupStateDetector.calculateProgressPercentage(0, 5))
        assertEquals(20, SetupStateDetector.calculateProgressPercentage(1, 5))
        assertEquals(40, SetupStateDetector.calculateProgressPercentage(2, 5))
        assertEquals(60, SetupStateDetector.calculateProgressPercentage(3, 5))
        assertEquals(80, SetupStateDetector.calculateProgressPercentage(4, 5))
        assertEquals(100, SetupStateDetector.calculateProgressPercentage(5, 5))

        // Clamping edge cases
        assertEquals(0, SetupStateDetector.calculateProgressPercentage(-1, 4))
        assertEquals(100, SetupStateDetector.calculateProgressPercentage(5, 4))
        assertEquals(0, SetupStateDetector.calculateProgressPercentage(2, 0))
    }

    @Test
    fun testAndroid13Detection() {
        assertFalse(SetupStateDetector.isAndroid13OrHigher(30)) // Android 11
        assertFalse(SetupStateDetector.isAndroid13OrHigher(31)) // Android 12
        assertFalse(SetupStateDetector.isAndroid13OrHigher(32)) // Android 12L
        assertTrue(SetupStateDetector.isAndroid13OrHigher(33))  // Android 13 (Tiramisu)
        assertTrue(SetupStateDetector.isAndroid13OrHigher(34))  // Android 14 (UpsideDownCake)
        assertTrue(SetupStateDetector.isAndroid13OrHigher(35))  // Android 15 (VanillaIceCream)
    }

    @Test
    fun testSetupWizardStateCounting() {
        val emptyState = SetupWizardState()
        assertEquals(0, emptyState.completedStepsCount)
        assertFalse(emptyState.isAllCompleted)

        val halfState = SetupWizardState(
            isRestrictedSettingsUnlocked = true,
            isAccessibilityActive = true,
            isBatteryOptimizationExempt = false,
            isWifiConnected = false,
            isCameraPermissionGranted = false
        )
        assertEquals(2, halfState.completedStepsCount)
        assertFalse(halfState.isAllCompleted)

        val completeState = SetupWizardState(
            isRestrictedSettingsUnlocked = true,
            isAccessibilityActive = true,
            isBatteryOptimizationExempt = true,
            isWifiConnected = true,
            isCameraPermissionGranted = true
        )
        assertEquals(5, completeState.completedStepsCount)
        assertTrue(completeState.isAllCompleted)
    }

    @Test
    fun testBootReceiverPackageReplacedActionMatching() {
        val packageReplacedAction = android.content.Intent.ACTION_MY_PACKAGE_REPLACED
        assertEquals("android.intent.action.MY_PACKAGE_REPLACED", packageReplacedAction)

        val supportedActions = setOf(
            android.content.Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            android.content.Intent.ACTION_MY_PACKAGE_REPLACED
        )
        assertTrue(supportedActions.contains("android.intent.action.MY_PACKAGE_REPLACED"))
        assertTrue(supportedActions.contains("android.intent.action.BOOT_COMPLETED"))
        assertTrue(supportedActions.contains("android.intent.action.QUICKBOOT_POWERON"))
        assertFalse(supportedActions.contains("android.intent.action.ACTION_POWER_CONNECTED"))
    }
}
