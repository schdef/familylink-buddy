package com.familylink.buddy.child.data

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.util.Log
import com.familylink.buddy.child.service.WifiAccessibilityHelperService
import com.familylink.buddy.child.ui.SetupGuideHelper

/**
 * Helper to auto-recover and persist Accessibility Service enabled state across app updates,
 * device reboots, and service unbinds using android.permission.WRITE_SECURE_SETTINGS.
 */
object AccessibilityAutoRecovery {
    private const val TAG = "AccessibilityAutoRecovery"

    /**
     * Checks if WRITE_SECURE_SETTINGS has been granted (typically via ADB).
     */
    fun isWriteSecureSettingsGranted(context: Context): Boolean {
        return try {
            context.checkCallingOrSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            Log.w(TAG, "Error checking WRITE_SECURE_SETTINGS permission", e)
            false
        }
    }

    /**
     * Pure logic helper to construct the updated ENABLED_ACCESSIBILITY_SERVICES string.
     */
    fun buildUpdatedAccessibilityServices(
        currentServices: String?,
        packageName: String,
        serviceClassName: String
    ): String {
        val targetService = "$packageName/$serviceClassName"
        if (currentServices.isNullOrBlank()) {
            return targetService
        }

        val services = currentServices.split(":")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toMutableList()

        val alreadyPresent = services.any {
            it.equals(targetService, ignoreCase = true) ||
                    (it.contains(packageName) && it.contains(serviceClassName.substringAfterLast('.')))
        }

        if (!alreadyPresent) {
            services.add(targetService)
        }

        return services.joinToString(":")
    }

    /**
     * Attempts to automatically re-enable the Accessibility Service if disabled.
     * Returns true if already enabled or if successfully re-enabled via WRITE_SECURE_SETTINGS.
     */
    fun tryAutoEnableAccessibility(context: Context): Boolean {
        try {
            if (SetupGuideHelper.isAccessibilityServiceEnabled(context)) {
                Log.d(TAG, "Accessibility Service is already enabled.")
                return true
            }

            if (!isWriteSecureSettingsGranted(context)) {
                Log.w(TAG, "Cannot auto-enable Accessibility: WRITE_SECURE_SETTINGS not granted.")
                return false
            }

            val cr = context.contentResolver
            val currentServices = Settings.Secure.getString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            val updatedServices = buildUpdatedAccessibilityServices(
                currentServices = currentServices,
                packageName = context.packageName,
                serviceClassName = WifiAccessibilityHelperService::class.java.name
            )

            val putServicesSuccess = Settings.Secure.putString(
                cr,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                updatedServices
            )
            val putEnabledSuccess = Settings.Secure.putInt(
                cr,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                1
            )

            Log.i(TAG, "Accessibility auto-recovery executed. Services updated: $putServicesSuccess, Enabled: $putEnabledSuccess")
            return putServicesSuccess && putEnabledSuccess
        } catch (e: Exception) {
            Log.e(TAG, "Exception during tryAutoEnableAccessibility", e)
            return false
        }
    }
}
