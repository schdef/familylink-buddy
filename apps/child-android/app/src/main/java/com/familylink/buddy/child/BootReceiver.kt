package com.familylink.buddy.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import com.familylink.buddy.child.data.AccessibilityAutoRecovery
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.service.LocalHttpServer
import com.familylink.buddy.child.service.WidgetUpdateService

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "Received broadcast action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "com.familylink.buddy.child.ACTION_INSTALL_STATUS") {

            val appContext = context.applicationContext ?: context

            // Auto-recover accessibility service if WRITE_SECURE_SETTINGS is granted
            try {
                AccessibilityAutoRecovery.tryAutoEnableAccessibility(appContext)
            } catch (e: Exception) {
                Log.e(TAG, "Failed auto-recovering accessibility: ${e.message}", e)
            }

            // Restart LocalHttpServer immediately upon boot or APK update
            try {
                val repository = FamilyTimeRepository(appContext)
                LocalHttpServer.startServer(appContext, repository)
            } catch (e: Exception) {
                Log.e(TAG, "Failed starting LocalHttpServer: ${e.message}", e)
            }

            // Start or restart WidgetUpdateService foreground service
            val serviceIntent = Intent(appContext, WidgetUpdateService::class.java).apply {
                this.action = WidgetUpdateService.ACTION_START
            }
            try {
                ContextCompat.startForegroundService(appContext, serviceIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed starting WidgetUpdateService: ${e.message}", e)
            }
        }
    }
}
