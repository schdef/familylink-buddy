package com.familylink.buddy.child.data

/**
 * Detects whether a foreground or accessibility event represents an unauthorized attempt
 * by the child to modify or disable accessibility services, remove permissions,
 * or uninstall FamilyLink Buddy.
 */
object AntiTamperDetector {

    private val SETTINGS_PACKAGES = setOf(
        "com.android.settings",
        "com.google.android.settings",
        "com.google.android.settings.intelligence",
        "com.miui.securitycenter",
        "com.samsung.android.app.telephonyui",
        "com.coloros.safecenter",
        "com.huawei.systemmanager"
    )

    /**
     * Checks if a package belongs to Android System Settings or manufacturer security centers.
     */
    fun isSettingsApp(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        val lower = packageName.lowercase()
        return SETTINGS_PACKAGES.contains(lower) || lower.endsWith(".settings")
    }

    /**
     * Determines whether the given window / event state indicates an attempt to modify
     * or disable accessibility services or force stop / uninstall the FamilyLink Buddy app.
     */
    fun isAccessibilityOrSettingsTamperAttempt(
        packageName: String?,
        className: String? = null,
        windowTexts: List<String> = emptyList()
    ): Boolean {
        if (!isSettingsApp(packageName)) return false

        val cls = className?.lowercase() ?: ""
        val isAccessibilityClass = cls.contains("accessibility") ||
                cls.contains("toggleservice") ||
                cls.contains("installedservices")

        val combinedText = windowTexts.joinToString(" ").lowercase()
        val mentionsAccessibility = combinedText.contains("bedienungshilfe") ||
                combinedText.contains("accessibility") ||
                combinedText.contains("barrierefreiheit") ||
                combinedText.contains("eingabehilfe")

        val mentionsOurApp = combinedText.contains("familylink") ||
                combinedText.contains("buddy") ||
                combinedText.contains("wifiaccessibility")

        val mentionsDisableOrUninstall = combinedText.contains("deinstallieren") ||
                combinedText.contains("uninstall") ||
                combinedText.contains("stoppen erzwingen") ||
                combinedText.contains("force stop") ||
                combinedText.contains("deaktivieren") ||
                combinedText.contains("disable") ||
                combinedText.contains("ausschalten")

        // Block if user is in an accessibility settings class
        if (isAccessibilityClass) {
            return true
        }

        // Block if user is looking at accessibility settings referencing our service
        if (mentionsAccessibility && mentionsOurApp) {
            return true
        }

        // Block if user is in app info settings trying to disable / uninstall our app
        if (mentionsOurApp && mentionsDisableOrUninstall) {
            return true
        }

        // Block if in a settings sub-page explicitly dealing with accessibility
        if (mentionsAccessibility && cls.contains("subsettings")) {
            return true
        }

        return false
    }

    /**
     * Evaluates whether anti-tamper action should be executed.
     * Takes into account PIN configuration and temporary parent unlock status.
     */
    fun shouldEnforceTamperProtection(
        packageName: String?,
        className: String? = null,
        windowTexts: List<String> = emptyList(),
        isPinConfigured: Boolean,
        isParentUnlocked: Boolean
    ): Boolean {
        if (!isPinConfigured) return false
        if (isParentUnlocked) return false
        return isAccessibilityOrSettingsTamperAttempt(packageName, className, windowTexts)
    }
}
