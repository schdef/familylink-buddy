package com.familylink.buddy.child.data

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

object InstalledAppsManager {

    private const val TAG = "InstalledAppsManager"

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
     * filtering out the child application itself, and returning them sorted by label.
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

        val ownPackage = context.packageName
        val seen = mutableSetOf<String>()
        val result = mutableListOf<InstalledAppInfo>()

        for (resolveInfo in resolveInfos) {
            val pkg = resolveInfo.activityInfo?.packageName ?: continue
            if (pkg == ownPackage || seen.contains(pkg)) continue
            seen.add(pkg)

            val label = try {
                resolveInfo.loadLabel(pm)?.toString()?.trim() ?: pkg
            } catch (e: Exception) {
                pkg
            }

            val finalLabel = if (label.isNotBlank()) label else pkg
            result.add(InstalledAppInfo(packageName = pkg, label = finalLabel))
        }

        return result
            .sortedBy { it.label.lowercase() }
            .map { it.toMap() }
    }
}
