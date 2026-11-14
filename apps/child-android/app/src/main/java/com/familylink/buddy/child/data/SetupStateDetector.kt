package com.familylink.buddy.child.data

/**
 * Encapsulates setup wizard progress and state detection logic.
 */
data class SetupWizardState(
    val isRestrictedSettingsUnlocked: Boolean = false,
    val isAccessibilityActive: Boolean = false,
    val isBatteryOptimizationExempt: Boolean = false,
    val isWifiConnected: Boolean = false,
    val localIp: String = "127.0.0.1",
    val localPort: Int = 8085,
    val pairingPayload: String = "",
    val isPinConfigured: Boolean = false,
    val isCameraPermissionGranted: Boolean = false
) {
    val completedStepsCount: Int
        get() {
            var count = 0
            if (isRestrictedSettingsUnlocked) count++
            if (isAccessibilityActive) count++
            if (isBatteryOptimizationExempt) count++
            if (isWifiConnected) count++
            if (isCameraPermissionGranted) count++
            return count
        }

    val isAllCompleted: Boolean
        get() = completedStepsCount == 5
}

object SetupStateDetector {

    /**
     * Calculates the progress percentage (0 to 100) based on completed steps.
     */
    fun calculateProgressPercentage(completedSteps: Int, totalSteps: Int = 5): Int {
        if (totalSteps <= 0) return 0
        return ((completedSteps.coerceIn(0, totalSteps).toDouble() / totalSteps) * 100).toInt()
    }

    /**
     * Checks if the current Android version is Android 13 (API 33, Tiramisu) or higher,
     * where restricted settings apply.
     */
    fun isAndroid13OrHigher(sdkInt: Int = android.os.Build.VERSION.SDK_INT): Boolean {
        return sdkInt >= 33 // Build.VERSION_CODES.TIRAMISU
    }
}
