package com.familylink.buddy.child.data

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

object InstalledAppsManager {

    private const val TAG = "InstalledAppsManager"
    const val GOOGLE_SEARCH_PACKAGE = "com.google.android.googlequicksearchbox"

    val EXCLUDED_PACKAGES = setOf(
        "com.spotify.music",
        "com.android.settings",
        "com.google.android.settings",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.android.phone",
        "com.google.android.dialer.service",
        "com.android.server.telecom",
        "com.google.android.contacts",
        "com.android.contacts",
        "com.android.systemui"
    )

    /**
     * Checks if a package is a Family Link allowed / essential system app
     * (Spotify, Settings, System dialer/phone, or the child companion itself)
     * which must NOT appear in the blockable apps list.
     */
    fun isAllowedExcludedApp(
        context: Context?,
        packageName: String,
        ownPackage: String? = context?.packageName
    ): Boolean {
        if (packageName.isBlank()) return true
        val lower = packageName.lowercase()
        if (ownPackage != null && lower == ownPackage.lowercase()) return true
        if (lower == "com.spotify.music") return true
        if (AntiTamperDetector.isSettingsApp(lower)) return true
        if (EXCLUDED_PACKAGES.contains(lower)) return true
        if (lower.contains("dialer") || lower.contains(".phone")) return true
        try {
            val telecomManager = context?.getSystemService(Context.TELECOM_SERVICE) as? android.telecom.TelecomManager
            val defaultDialer = telecomManager?.defaultDialerPackage
            if (!defaultDialer.isNullOrBlank() && defaultDialer.equals(packageName, ignoreCase = true)) {
                return true
            }
        } catch (e: Exception) {
            // ignore
        }
        return false
    }

    data class InstalledAppInfo(
        val packageName: String,
        val label: String
    ) {
        fun toMap(): Map<String, String> = mapOf(
            "packageName" to packageName,
            "label" to label
        )
    }

    /**
     * Queries all installed launcher applications on the device,
     * filtering out the child application itself and allowed apps (Spotify, Settings, Dialer, SystemUI),
     * ensuring com.google.android.googlequicksearchbox is included if installed,
     * and returning them sorted by label.
     */
    fun scanInstalledLauncherApps(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolveInfos = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(
                    mainIntent,
                    PackageManager.ResolveInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(mainIntent, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying launcher intent activities", e)
            emptyList()
        }

        val seen = mutableSetOf<String>()
        val result = mutableListOf<InstalledAppInfo>()

        for (resolveInfo in resolveInfos) {
            val pkg = resolveInfo.activityInfo?.packageName ?: continue
            if (seen.contains(pkg) || isAllowedExcludedApp(context, pkg)) continue
            seen.add(pkg)

            val label = try {
                resolveInfo.loadLabel(pm)?.toString()?.trim() ?: pkg
            } catch (e: Exception) {
                pkg
            }

            val finalLabel = if (label.isNotBlank()) label else pkg
            result.add(InstalledAppInfo(packageName = pkg, label = finalLabel))
        }

        // Ensure com.google.android.googlequicksearchbox is included even if it lacks standard launcher intent
        if (!seen.contains(GOOGLE_SEARCH_PACKAGE) && !isAllowedExcludedApp(context, GOOGLE_SEARCH_PACKAGE)) {
            try {
                val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getApplicationInfo(GOOGLE_SEARCH_PACKAGE, PackageManager.ApplicationInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getApplicationInfo(GOOGLE_SEARCH_PACKAGE, 0)
                }
                val label = pm.getApplicationLabel(appInfo).toString().trim()
                val finalLabel = if (label.isNotBlank()) label else "Google"
                result.add(InstalledAppInfo(packageName = GOOGLE_SEARCH_PACKAGE, label = finalLabel))
                seen.add(GOOGLE_SEARCH_PACKAGE)
            } catch (e: Exception) {
                // If not installed on device / emulator
            }
        }

        return result
            .sortedBy { it.label.lowercase() }
            .map { it.toMap() }
    }
}
