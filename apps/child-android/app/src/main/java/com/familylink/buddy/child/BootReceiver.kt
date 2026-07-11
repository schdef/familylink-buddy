package com.familylink.buddy.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.familylink.buddy.child.service.WidgetUpdateService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            val serviceIntent = Intent(context, WidgetUpdateService::class.java).apply {
                action = WidgetUpdateService.ACTION_START
            }
            ContextCompat.startForegroundService(context, serviceIntent)
        }
    }
}
