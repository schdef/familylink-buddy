package com.familylink.buddy.child.service

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.glance.appwidget.updateAll
import com.familylink.buddy.child.MainActivity
import com.familylink.buddy.child.data.FamilyTimeData
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.widget.FamilyBuddyWidget
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first

class WidgetUpdateService : Service() {

    companion object {
        private const val TAG = "WidgetUpdateService"
        private const val CHANNEL_ID = "background_keep_alive"
        private const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
    }

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var repository: FamilyTimeRepository
    private var tickerJob: Job? = null
    private var isScreenOn = true

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> {
                    Log.d(TAG, "Screen ON: Starting ticker")
                    isScreenOn = true
                    startTicker()
                }
                Intent.ACTION_SCREEN_OFF -> {
                    Log.d(TAG, "Screen OFF: Stopping ticker")
                    isScreenOn = false
                    stopTicker()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        repository = FamilyTimeRepository(applicationContext)
        createNotificationChannel()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand action: $action")

        if (action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundServiceCompat()
        startTicker()

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)
        serviceScope.cancel()
        Log.d(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundServiceCompat() {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FamilyLink Buddy Active")
            .setContentText("Keeping widget up-to-date in real-time.")
            .setSmallIcon(android.R.drawable.ic_menu_myplaces)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startTicker() {
        if (tickerJob?.isActive == true) return

        tickerJob = serviceScope.launch {
            while (isActive && isScreenOn) {
                // Fetch current time details
                val currentData = repository.familyTimeData.first()

                if (currentData.totalRemainingMinutes > 0) {
                    val updatedAppUsages = currentData.appUsages.map { app ->
                        // Simulate usage incrementing by 1 minute for active apps
                        val shouldIncrement = app.packageName == "com.google.android.youtube" || 
                                              app.packageName == "com.mojang.minecraftpe"
                        if (shouldIncrement && app.usedMinutes < app.limitMinutes) {
                            app.copy(usedMinutes = app.usedMinutes + 1)
                        } else app
                    }

                    val updatedData = currentData.copy(
                        totalRemainingMinutes = (currentData.totalRemainingMinutes - 1).coerceAtLeast(0),
                        appUsages = updatedAppUsages,
                        lastUpdatedMillis = System.currentTimeMillis()
                    )

                    repository.updateFamilyTimeData(updatedData)
                    Log.d(TAG, "Ticker updated: ${updatedData.totalRemainingMinutes} min remaining")
                    
                    // Force refresh all widget instances
                    FamilyBuddyWidget().updateAll(applicationContext)
                }
                
                // For MVP testing, decrement every 10 seconds instead of 60 seconds so changes are visible
                delay(10_000)
            }
        }
    }

    private fun stopTicker() {
        tickerJob?.cancel()
        tickerJob = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Device Status (Background Keep-Alive)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Runs the background sync engine for real-time widgets. Toggling this off hides the icon while retaining functionality."
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
