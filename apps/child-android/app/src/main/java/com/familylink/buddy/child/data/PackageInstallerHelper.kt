package com.familylink.buddy.child.data

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import com.familylink.buddy.child.BootReceiver
import java.io.File

/**
 * Helper to install APK updates using PackageInstaller Session (in-place self update)
 * with graceful fallback to FileProvider Intent.ACTION_VIEW.
 */
object PackageInstallerHelper {
    private const val TAG = "PackageInstallerHelper"

    /**
     * Checks if the APK file exists and has a plausible size (> 1MB).
     */
    fun isApkValid(apkFile: File?): Boolean {
        return apkFile != null && apkFile.exists() && apkFile.isFile && apkFile.length() > 1024 * 1024
    }

    /**
     * Attempts to install an APK file.
     * Uses PackageInstaller.Session first so that Android 12+ treats the update as an in-place upgrade,
     * avoiding restricted settings sideload penalties on Android 13/14.
     * Falls back to FileProvider + Intent.ACTION_VIEW if session creation or commit fails.
     */
    fun installApk(context: Context, apkFile: File): Boolean {
        if (!isApkValid(apkFile)) {
            Log.e(TAG, "Cannot install APK: file is invalid or too small (${apkFile.length()} bytes)")
            return false
        }

        // Try session-based installer
        try {
            val packageInstaller = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }

            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            apkFile.inputStream().use { input ->
                session.openWrite("package", 0, apkFile.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }

            val intent = Intent(context, BootReceiver::class.java).apply {
                action = "com.familylink.buddy.child.ACTION_INSTALL_STATUS"
                putExtra(PackageInstaller.EXTRA_SESSION_ID, sessionId)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                sessionId,
                intent,
                flags
            )

            session.commit(pendingIntent.intentSender)
            session.close()
            Log.i(TAG, "Committed PackageInstaller session $sessionId for ${apkFile.name}")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "PackageInstaller session failed, falling back to FileProvider Intent: ${e.message}", e)
        }

        // Fallback: FileProvider + Intent.ACTION_VIEW
        return installViaFileProviderFallback(context, apkFile)
    }

    /**
     * Fallback installation via FileProvider and Intent.ACTION_VIEW.
     */
    fun installViaFileProviderFallback(context: Context, apkFile: File): Boolean {
        return try {
            val apkUri = FileProvider.getUriForFile(
                context,
                "com.familylink.buddy.child.fileprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(installIntent)
            Log.i(TAG, "Launched FileProvider install intent for ${apkFile.name}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed launching FileProvider install intent: ${e.message}", e)
            false
        }
    }
}
