package com.familylink.buddy.child.service

import android.app.*
import com.familylink.buddy.child.R
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
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.widget.FamilyBuddyWidget
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.provider.Settings
import java.util.Locale

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
    private var dbObserverJob: Job? = null
    private var isScreenOn = true

    // Overlay state variables
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var isOverlayShown = false
    private var overlaySecondsRemaining = 180
    private var overlaySecondsRemainingFloat = 180f
    private var overlayTickerJob: Job? = null
    private var currentSizePreset = 1 // 0 = Small, 1 = Medium, 2 = Large

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

        startDatabaseObserver()
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
        hideOverlay()
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
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
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

    private fun startDatabaseObserver() {
        if (dbObserverJob?.isActive == true) return
        dbObserverJob = serviceScope.launch {
            repository.familyTimeData.collect { data ->
                withContext(Dispatchers.Main) {
                    handleTimeDataChanged(data)
                }
            }
        }
    }

    private fun handleTimeDataChanged(data: FamilyTimeData) {
        val remaining = data.totalRemainingMinutes
        if (remaining <= 3 && remaining > 0) {
            if (!isOverlayShown) {
                overlaySecondsRemaining = remaining * 60
                showOverlay()
            } else {
                val expectedSeconds = remaining * 60
                if (Math.abs(overlaySecondsRemaining - expectedSeconds) > 15) {
                    overlaySecondsRemaining = expectedSeconds
                }
            }
        } else {
            hideOverlay()
        }
    }

    private fun showOverlay() {
        if (isOverlayShown) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Cannot show overlay: Overlay permission not granted")
            return
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        overlayView = LayoutInflater.from(this).inflate(com.familylink.buddy.child.R.layout.overlay_countdown, null)

        val (widthPx, heightPx) = getPresetDimensions(currentSizePreset)

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        overlayParams = WindowManager.LayoutParams(
            widthPx,
            heightPx,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 200
        }

        setupDragListener()

        val sizeBtn = overlayView?.findViewById<Button>(com.familylink.buddy.child.R.id.sizeToggleButton)
        sizeBtn?.setOnClickListener {
            cycleSizePreset()
        }

        try {
            windowManager?.addView(overlayView, overlayParams)
            isOverlayShown = true
            Log.d(TAG, "Overlay added successfully")
            startOverlayCountdown()
        } catch (e: Exception) {
            Log.e(TAG, "Error adding overlay view: ${e.message}")
        }
    }

    private fun hideOverlay() {
        if (!isOverlayShown) return
        overlayTickerJob?.cancel()
        overlayTickerJob = null

        val wm = windowManager
        val view = overlayView

        windowManager = null
        overlayView = null
        overlayParams = null
        isOverlayShown = false

        if (wm != null && view != null) {
            try {
                wm.removeView(view)
                Log.d(TAG, "Overlay removed successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlay: ${e.message}")
            }
        }
    }

    private fun getPresetDimensions(preset: Int): Pair<Int, Int> {
        val density = resources.displayMetrics.density
        val widthDp = when (preset) {
            0 -> 160
            2 -> 320
            else -> 240
        }
        val heightDp = when (preset) {
            0 -> 80
            2 -> 160
            else -> 120
        }
        return Pair((widthDp * density).toInt(), (heightDp * density).toInt())
    }

    private fun cycleSizePreset() {
        currentSizePreset = (currentSizePreset + 1) % 3
        val (width, height) = getPresetDimensions(currentSizePreset)
        overlayParams?.width = width
        overlayParams?.height = height
        try {
            windowManager?.updateViewLayout(overlayView, overlayParams)
            Log.d(TAG, "Overlay resized to preset $currentSizePreset: $width x $height")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resize overlay: ${e.message}")
        }
    }

    private fun setupDragListener() {
        overlayView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = overlayParams?.x ?: 0
                        initialY = overlayParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        overlayParams?.x = initialX + dx
                        overlayParams?.y = initialY + dy
                        try {
                            windowManager?.updateViewLayout(overlayView, overlayParams)
                        } catch (e: Exception) {
                            // View might have been removed
                        }
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun startOverlayCountdown() {
        overlayTickerJob?.cancel()
        overlayTickerJob = serviceScope.launch(Dispatchers.Main) {
            overlaySecondsRemainingFloat = overlaySecondsRemaining.toFloat()

            val animationContainer = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.animationContainer)
            val earthImage = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.earthImage)
            val launchpadImage = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.launchpadImage)
            val rocketImage = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.rocketImage)
            val countdownLabel = overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownLabel)

            while (isActive && isOverlayShown) {
                val t = overlaySecondsRemainingFloat

                // 1. Update Countdown Text once per second
                val displaySeconds = Math.ceil(t.toDouble()).toInt().coerceAtLeast(0)
                val minutes = displaySeconds / 60
                val seconds = displaySeconds % 60
                val timeStr = String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
                overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = timeStr

                // 2. Handle Space Mission Animation Stages
                if (t <= 30f && t > 0f) {
                    animationContainer?.visibility = View.VISIBLE

                    if (t > 20f) {
                        // Stage 1: Preparing (30s to 20s)
                        earthImage?.visibility = View.GONE
                        launchpadImage?.visibility = View.VISIBLE
                        rocketImage?.visibility = View.VISIBLE

                        countdownLabel?.text = getString(R.string.rocket_preparing)

                        val containerHeight = animationContainer?.height ?: 0
                        val rocketHeight = rocketImage?.height ?: 0
                        val bottomY = (containerHeight / 2f) - (rocketHeight / 2f) - (4f * resources.displayMetrics.density)
                        
                        val shakeX = (Random.nextFloat() - 0.5f) * 2f * resources.displayMetrics.density
                        val shakeY = (Random.nextFloat() - 0.5f) * 2f * resources.displayMetrics.density

                        rocketImage?.translationX = shakeX
                        rocketImage?.translationY = bottomY + shakeY
                        rocketImage?.rotation = 0f
                        launchpadImage?.translationY = 0f

                    } else if (t > 10f) {
                        // Stage 2: Launching (20s to 10s)
                        earthImage?.visibility = View.GONE
                        launchpadImage?.visibility = View.VISIBLE
                        rocketImage?.visibility = View.VISIBLE

                        countdownLabel?.text = getString(R.string.rocket_launching)

                        val progress = (20f - t) / 10f // 0.0 to 1.0

                        val containerHeight = animationContainer?.height ?: 0
                        val rocketHeight = rocketImage?.height ?: 0
                        val bottomY = (containerHeight / 2f) - (rocketHeight / 2f) - (4f * resources.displayMetrics.density)

                        val travelDistance = bottomY + (rocketHeight * 2f)
                        val currentY = bottomY - (progress * travelDistance)

                        val shakeX = (Random.nextFloat() - 0.5f) * 3f * resources.displayMetrics.density * (1f - progress)
                        
                        rocketImage?.translationX = shakeX
                        rocketImage?.translationY = currentY
                        rocketImage?.rotation = 0f

                        launchpadImage?.translationY = progress * 40f * resources.displayMetrics.density

                    } else {
                        // Stage 3: Orbiting Earth (10s to 0s)
                        launchpadImage?.visibility = View.GONE
                        earthImage?.visibility = View.VISIBLE
                        rocketImage?.visibility = View.VISIBLE

                        countdownLabel?.text = getString(R.string.rocket_orbit)

                        val progress = (10f - t) / 10f // 0.0 to 1.0
                        val angle = progress * 2f * Math.PI.toFloat()

                        val radius = 22f * resources.displayMetrics.density

                        val orbX = radius * cos(angle)
                        val orbY = radius * sin(angle)

                        rocketImage?.translationX = orbX
                        rocketImage?.translationY = orbY

                        val angleDegrees = (angle * 180f / Math.PI.toFloat()) + 90f
                        rocketImage?.rotation = angleDegrees
                    }
                } else {
                    animationContainer?.visibility = View.GONE
                    countdownLabel?.text = getString(R.string.overlay_label)
                }

                if (t <= 0f) {
                    overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = "00:00"
                    break
                }

                delay(50)
                overlaySecondsRemainingFloat -= 0.05f
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.notification_channel_desc)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
