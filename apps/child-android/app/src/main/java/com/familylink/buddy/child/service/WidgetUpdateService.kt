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
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.Timestamp
import com.familylink.buddy.child.data.AppUsage
import com.familylink.buddy.child.data.VolumeState
import android.media.AudioManager
import android.provider.Settings
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import java.util.Locale
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.app.usage.UsageStats
import android.content.pm.PackageManager
import java.util.Calendar

class WidgetUpdateService : Service() {

    companion object {
        private const val TAG = "WidgetUpdateService"
        private const val CHANNEL_ID = "background_keep_alive"
        private const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_MOCK_ROCKET = "ACTION_MOCK_ROCKET"
        const val ACTION_COIN_AWARD = "com.familylink.buddy.child.ACTION_COIN_AWARD"
    }

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var repository: FamilyTimeRepository
    private var tickerJob: Job? = null
    private var dbObserverJob: Job? = null
    private var isScreenOn = true
    private var localHttpServer: LocalHttpServer? = null
    private var foregroundMonitorJob: Job? = null
    private var foregroundLockedApp: AppUsage? = null

    // Overlay state variables
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var isOverlayShown = false
    private var isMockRocketRunning = false
    private var overlaySecondsRemaining = 180
    private var overlayStartTimeMs = 0L
    private var overlayTotalSeconds = 180
    private var overlayTickerJob: Job? = null
    private var volumeReportJob: Job? = null
    private var currentSizePreset = 2 // 0 = Small, 1 = Medium, 2 = Large

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
        getSharedPreferences("widget_service_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean("service_running", true).apply()
        repository = FamilyTimeRepository(applicationContext)
        createNotificationChannel()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)

        startDatabaseObserver()

        localHttpServer = LocalHttpServer(applicationContext, repository).apply {
            start()
        }

        startFirestoreListener()
        registerVolumeObserver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand action: $action")

        if (action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundServiceCompat()

        if (action == ACTION_MOCK_ROCKET) {
            triggerMockRocketLaunch()
        } else {
            startTicker()
            startForegroundMonitor()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        getSharedPreferences("widget_service_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean("service_running", false).apply()
        unregisterReceiver(screenReceiver)
        hideOverlay()
        stopForegroundMonitor()
        firestoreListenerRegistration?.remove()
        firestoreListenerRegistration = null
        unregisterVolumeObserver()
        serviceScope.cancel()
        localHttpServer?.stop()
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

                if (isMockRocketRunning) {
                    delay(10_000)
                    continue
                }

                if (currentData.totalRemainingMinutes > 0) {
                    val updatedAppUsages = if (checkUsageAccessPermission()) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                            val calendar = Calendar.getInstance()
                            calendar.set(Calendar.HOUR_OF_DAY, 0)
                            calendar.set(Calendar.MINUTE, 0)
                            calendar.set(Calendar.SECOND, 0)
                            val startTime = calendar.timeInMillis
                            val endTime = System.currentTimeMillis()
                            
                            val usageStats = usageStatsManager?.queryAndAggregateUsageStats(startTime, endTime)
                            currentData.appUsages.map { app ->
                                val timeInForegroundMs = usageStats?.get(app.packageName)?.totalTimeInForeground ?: 0L
                                val usedMin = (timeInForegroundMs / (1000 * 60)).toInt()
                                app.copy(usedMinutes = usedMin)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error querying usage stats in ticker", e)
                            currentData.appUsages
                        }
                    } else {
                        // Simulate usage incrementing by 1 minute for active apps
                        currentData.appUsages.map { app ->
                            val shouldIncrement = app.packageName == "com.google.android.youtube" || 
                                                  app.packageName == "com.mojang.minecraftpe"
                            if (shouldIncrement && app.usedMinutes < app.limitMinutes) {
                                app.copy(usedMinutes = app.usedMinutes + 1)
                            } else app
                        }
                    }

                    val updatedData = currentData.copy(
                        appUsages = updatedAppUsages,
                        lastUpdatedMillis = System.currentTimeMillis()
                    )

                    repository.updateFamilyTimeData(updatedData)
                    Log.d(TAG, "Ticker updated: ${updatedData.totalRemainingMinutes} min remaining (no local decrement)")
                    
                    // Force refresh all widget instances
                    FamilyBuddyWidget().updateAll(applicationContext)
                }
                
                // Use 10s intervals for fast emulator testing; otherwise, use real-time 60s intervals
                val tickInterval = if (com.familylink.buddy.child.BuildConfig.USE_EMULATOR) 10_000L else 60_000L
                delay(tickInterval)
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

    private fun getHomePackageName(): String {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolveInfo = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolveInfo?.activityInfo?.packageName ?: ""
    }

    private fun getForegroundPackageName(): String? {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val time = System.currentTimeMillis()
        
        // Kleineres Fenster + INTERVAL_BEST
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST, time - 10_000, time)
        
        // Erweiterter Filter für System-Packages
        val systemPackages = setOf(
            "com.android.systemui",
            "com.android.launcher",
            "com.android.launcher3", 
            "com.google.android.apps.nexuslauncher",
            "com.sec.android.app.launcher",   // Samsung
            "com.miui.home",                   // Xiaomi
            "com.huawei.android.launcher",     // Huawei
            packageName                        // eigene App
        )
        val homePkg = getHomePackageName()
        
        return stats
            ?.filter { it.packageName !in systemPackages && it.packageName != homePkg }
            ?.maxByOrNull { it.lastTimeUsed }
            ?.packageName
    }

    private fun checkForegroundAndLockState(data: FamilyTimeData) {
        val remaining = data.totalRemainingMinutes
        val foregroundPkg = getForegroundPackageName()

        // Find if foreground app is locked
        val fgLockedApp = if (foregroundPkg != null) {
            data.appUsages.firstOrNull { it.packageName == foregroundPkg && it.remainingMinutes <= 0 }
        } else {
            null
        }

        // Find if foreground app is going to be locked (remaining minutes <= 3 and > 0)
        val fgGoingToLockApp = if (foregroundPkg != null && fgLockedApp == null) {
            data.appUsages.firstOrNull { 
                it.packageName == foregroundPkg && 
                it.limitMinutes < 1440 && 
                it.remainingMinutes <= 3 && 
                it.remainingMinutes > 0 
            }
        } else {
            null
        }

        val shouldShow = (remaining <= 0) || (remaining <= 3 && remaining > 0) || (fgLockedApp != null) || (fgGoingToLockApp != null)

        if (shouldShow) {
            val previousAppPkg = foregroundLockedApp?.packageName
            val previousRemaining = overlaySecondsRemaining

            if (fgLockedApp != null) {
                foregroundLockedApp = fgLockedApp
                overlaySecondsRemaining = 0
            } else if (remaining <= 0) {
                foregroundLockedApp = null
                overlaySecondsRemaining = 0
            } else if (fgGoingToLockApp != null) {
                foregroundLockedApp = fgGoingToLockApp
                if (!isOverlayShown || previousAppPkg != fgGoingToLockApp.packageName) {
                    overlaySecondsRemaining = fgGoingToLockApp.remainingMinutes * 60
                }
            } else {
                foregroundLockedApp = null
                if (!isOverlayShown) {
                    overlaySecondsRemaining = remaining * 60
                }
            }

            if (!isOverlayShown) {
                overlayTotalSeconds = overlaySecondsRemaining
                overlayStartTimeMs = System.currentTimeMillis()
                showOverlay()
            } else {
                if (foregroundLockedApp?.packageName != previousAppPkg || Math.abs(overlaySecondsRemaining - previousRemaining) > 5) {
                    overlayTotalSeconds = overlaySecondsRemaining
                    overlayStartTimeMs = System.currentTimeMillis()
                }
            }
        } else {
            foregroundLockedApp = null
            isMockRocketRunning = false
            hideOverlay()
        }
    }

    private fun startForegroundMonitor() {
        if (foregroundMonitorJob?.isActive == true) return
        foregroundMonitorJob = serviceScope.launch {
            while (isActive) {
                if (isScreenOn) {
                    val currentData = repository.familyTimeData.first()
                    withContext(Dispatchers.Main) {
                        checkForegroundAndLockState(currentData)
                    }
                }
                delay(1000) // check every 1s
            }
        }
    }

    private fun stopForegroundMonitor() {
        foregroundMonitorJob?.cancel()
        foregroundMonitorJob = null
    }

    private fun checkUsageAccessPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.noteOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun handleTimeDataChanged(data: FamilyTimeData) {
        checkForegroundAndLockState(data)
    }

    private fun triggerMockRocketLaunch() {
        isMockRocketRunning = true
        overlaySecondsRemaining = 30
        overlayTotalSeconds = 30
        overlayStartTimeMs = System.currentTimeMillis()
        showOverlay()
        startOverlayCountdown()
        
        // Update DB so that companion layout mirrors active timer state
        serviceScope.launch {
            try {
                val current = repository.familyTimeData.first()
                val updated = current.copy(
                    totalRemainingMinutes = 1,
                    appUsages = current.appUsages.map {
                        it.copy(usedMinutes = it.limitMinutes - 1)
                    }
                )
                repository.updateFamilyTimeData(updated)
                FamilyBuddyWidget().updateAll(applicationContext)
            } catch (e: Exception) {
                Log.e(TAG, "Error updating repository for mock rocket launch", e)
            }
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

        val displayMetrics = resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val marginPx = (16 * displayMetrics.density).toInt()

        overlayParams = WindowManager.LayoutParams(
            widthPx,
            heightPx,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = screenWidth - widthPx - marginPx
            y = marginPx
        }

        applyImageSizesForPreset(currentSizePreset)
        setupDragListener()

        val sizeBtn = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.sizeToggleButton)
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
        isMockRocketRunning = false

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
            applyImageSizesForPreset(currentSizePreset)
            Log.d(TAG, "Overlay resized to preset $currentSizePreset: $width x $height")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resize overlay: ${e.message}")
        }
    }

    private fun applyImageSizesForPreset(preset: Int) {
        val density = resources.displayMetrics.density
        
        val rocketSize = when (preset) {
            0 -> 32f
            2 -> 76f
            else -> 50f
        } * density
        
        val earthSize = when (preset) {
            0 -> 36f
            2 -> 80f
            else -> 56f
        } * density
        
        val launchpadSize = when (preset) {
            0 -> 36f
            2 -> 80f
            else -> 56f
        } * density

        val rocket = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.rocketImage)
        val earth = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.earthImage)
        val launchpad = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.launchpadImage)

        rocket?.layoutParams = rocket?.layoutParams?.apply {
            width = rocketSize.toInt()
            height = rocketSize.toInt()
        }
        
        earth?.layoutParams = earth?.layoutParams?.apply {
            width = earthSize.toInt()
            height = earthSize.toInt()
        }
        
        launchpad?.layoutParams = launchpad?.layoutParams?.apply {
            width = launchpadSize.toInt()
            height = launchpadSize.toInt()
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
                    MotionEvent.ACTION_UP -> {
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
            val animationContainer = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.animationContainer)
            val earthImage = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.earthImage)
            val launchpadImage = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.launchpadImage)
            val rocketImage = overlayView?.findViewById<View>(com.familylink.buddy.child.R.id.rocketImage)
            val countdownLabel = overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownLabel)

            while (isActive && isOverlayShown) {
                // Fetch current DB details to check for active app locks
                val currentData = repository.familyTimeData.first()
                val fgLocked = foregroundLockedApp
                val isDeviceLocked = currentData.totalRemainingMinutes <= 0

                val elapsedMs = System.currentTimeMillis() - overlayStartTimeMs
                val remainingSeconds = (overlayTotalSeconds - elapsedMs / 1000f).coerceAtLeast(0f)

                if (isDeviceLocked || (fgLocked != null && fgLocked.remainingMinutes <= 0)) {
                    // App or Device Lock State: Show LOCK status and correct label
                    overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = getString(R.string.text_locked)
                    countdownLabel?.text = fgLocked?.appName ?: getString(R.string.lock_reason_device)

                    animationContainer?.visibility = View.VISIBLE
                    launchpadImage?.visibility = View.GONE
                    earthImage?.visibility = View.VISIBLE
                    rocketImage?.visibility = View.VISIBLE

                    // Rotate rocket orbiting Earth continuously
                    val angle = (System.currentTimeMillis() % 10000) / 10000f * 2f * Math.PI.toFloat()
                    val orbitRadiusDp = when (currentSizePreset) {
                        0 -> 28f
                        2 -> 72f
                        else -> 48f
                    }
                    val radius = orbitRadiusDp * resources.displayMetrics.density
                    rocketImage?.translationX = radius * cos(angle)
                    rocketImage?.translationY = radius * sin(angle)
                    rocketImage?.rotation = (angle * 180f / Math.PI.toFloat()) + 180f

                } else {
                    val t = remainingSeconds
                    val labelPrefix = fgLocked?.appName ?: getString(R.string.lock_reason_device)

                    // 1. Update Countdown Text once per second
                    val displaySeconds = Math.ceil(t.toDouble()).toInt().coerceAtLeast(0)
                    val minutes = displaySeconds / 60
                    val seconds = displaySeconds % 60
                    val timeStr = String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
                    overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = timeStr

                    // 2. Handle Space Mission Animation Stages
                    val stage1Start = overlayTotalSeconds.coerceAtMost(30).toFloat()
                    val stage2Start = (stage1Start - 10f).coerceAtLeast(0f)
                    val stage3Start = (stage1Start - 20f).coerceAtLeast(0f)

                    if (t <= stage1Start && t > 0f) {
                        animationContainer?.visibility = View.VISIBLE

                        if (t > stage2Start) {
                            // Stage 1: Preparing
                            earthImage?.visibility = View.GONE
                            launchpadImage?.visibility = View.VISIBLE
                            rocketImage?.visibility = View.VISIBLE

                            countdownLabel?.text = "$labelPrefix: ${getString(R.string.rocket_preparing)}"

                            val containerHeight = animationContainer?.height ?: 0
                            val rocketHeight = rocketImage?.height ?: 0
                            val bottomY = (containerHeight / 2f) - (rocketHeight / 2f) - (4f * resources.displayMetrics.density)
                            
                            val shakeX = (Random.nextFloat() - 0.5f) * 2f * resources.displayMetrics.density
                            val shakeY = (Random.nextFloat() - 0.5f) * 2f * resources.displayMetrics.density

                            rocketImage?.translationX = shakeX
                            rocketImage?.translationY = bottomY + shakeY
                            rocketImage?.rotation = 0f
                            launchpadImage?.translationY = 0f

                        } else if (t > stage3Start) {
                            // Stage 2: Launching
                            earthImage?.visibility = View.GONE
                            launchpadImage?.visibility = View.VISIBLE
                            rocketImage?.visibility = View.VISIBLE

                            countdownLabel?.text = "$labelPrefix: ${getString(R.string.rocket_launching)}"

                            val diff = stage1Start - stage2Start
                            val progress = if (diff > 0f) {
                                ((stage2Start - t) / (stage2Start - stage3Start)).coerceIn(0f, 1f)
                            } else 0f

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
                            // Stage 3: Orbiting Earth
                            launchpadImage?.visibility = View.GONE
                            earthImage?.visibility = View.VISIBLE
                            rocketImage?.visibility = View.VISIBLE

                            countdownLabel?.text = "$labelPrefix: ${getString(R.string.rocket_orbit)}"

                            val progress = if (stage3Start > 0f) {
                                ((stage3Start - t) / stage3Start).coerceIn(0f, 1f)
                            } else 1f
                            val angle = progress * 2f * Math.PI.toFloat()

                            val orbitRadiusDp = when (currentSizePreset) {
                                0 -> 28f
                                2 -> 72f
                                else -> 48f
                            }
                            val radius = orbitRadiusDp * resources.displayMetrics.density

                            val orbX = radius * cos(angle)
                            val orbY = radius * sin(angle)

                            rocketImage?.translationX = orbX
                            rocketImage?.translationY = orbY

                            val angleDegrees = (angle * 180f / Math.PI.toFloat()) + 180f
                            rocketImage?.rotation = angleDegrees
                        }
                    } else {
                        animationContainer?.visibility = View.GONE
                        countdownLabel?.text = labelPrefix
                    }

                    if (t <= 0f) {
                        overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = "00:00"
                        // Keep the overlay visible for 5 seconds after countdown ends, then hide
                        delay(5000)
                        hideOverlay()
                        break
                    }
                }

                delay(50)
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

    private var firestoreListenerRegistration: ListenerRegistration? = null
    private var lastExecutedCommandTimestamp: Long = 0
    private var lastExecutedCoinAwardTimestamp: Long = 0
    private var lastExecutedCommsSessionTimestamp: Long = 0
    private var volumeObserver: ContentObserver? = null

    private fun startFirestoreListener() {
        serviceScope.launch {
            repository.volumeState.collect { volumeState ->
                val token = volumeState.deviceToken
                if (token.isNotEmpty()) {
                    withContext(Dispatchers.Main) {
                        registerFirestoreListener(token)
                    }
                }
            }
        }
    }

    private fun registerVolumeObserver() {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                volumeReportJob?.cancel()
                volumeReportJob = serviceScope.launch {
                    delay(200) // Debounce
                    val volumeState = repository.volumeState.first()
                    val token = volumeState.deviceToken
                    if (token.isNotEmpty()) {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val mediaVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val ringtoneVol = audioManager.getStreamVolume(AudioManager.STREAM_RING)
                        val alarmVol = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                        val maxMedia = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val maxRingtone = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)
                        val maxAlarm = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)

                        val localState = VolumeState(
                            mediaVolume = mediaVol,
                            ringtoneVolume = ringtoneVol,
                            alarmVolume = alarmVol,
                            maxMediaVolume = maxMedia,
                            maxRingtoneVolume = maxRingtone,
                            maxAlarmVolume = maxAlarm,
                            isMuted = mediaVol == 0,
                            deviceToken = token
                        )
                        // Update local repository so the child UI changes instantly
                        repository.updateVolumeState(localState)

                        // Update Firestore report so parent gets notified
                        try {
                            val db = FirebaseFirestore.getInstance()
                            db.collection("pairings").document(token).update("volumeReport", hashMapOf(
                                "mediaVolume" to mediaVol,
                                "ringtoneVolume" to ringtoneVol,
                                "alarmVolume" to alarmVol,
                                "maxMediaVolume" to maxMedia,
                                "maxRingtoneVolume" to maxRingtone,
                                "maxAlarmVolume" to maxAlarm
                            ))
                            Log.d(TAG, "Local physical volume change detected and reported to Firestore")
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to update Firestore volume report on local change", e)
                        }
                    }
                }
            }
        }
        contentResolver.registerContentObserver(
            android.provider.Settings.System.CONTENT_URI,
            true,
            observer
        )
        volumeObserver = observer
        Log.d(TAG, "Registered system volume ContentObserver")
    }

    private fun unregisterVolumeObserver() {
        volumeObserver?.let {
            contentResolver.unregisterContentObserver(it)
            volumeObserver = null
            Log.d(TAG, "Unregistered system volume ContentObserver")
        }
    }

    private fun registerFirestoreListener(token: String) {
        firestoreListenerRegistration?.remove()
        try {
            val db = FirebaseFirestore.getInstance()
            firestoreListenerRegistration = db.collection("pairings").document(token)
                .addSnapshotListener { snapshot, error ->
                    if (error != null) {
                        Log.e(TAG, "Firestore listener error", error)
                        return@addSnapshotListener
                    }
                    if (snapshot != null && snapshot.exists()) {
                        handleFirestoreUpdate(snapshot.data ?: emptyMap(), token)
                    }
                }
            Log.d(TAG, "Registered Firestore listener for token: $token")
        } catch (e: Exception) {
            Log.e(TAG, "Error registering Firestore listener", e)
        }
    }

    private fun handleFirestoreUpdate(data: Map<String, Any>, token: String) {
        // 1. Process Volume Command
        val commandMap = data["volumeCommand"] as? Map<*, *>
        if (commandMap != null) {
            val stream = commandMap["stream"] as? String ?: "MEDIA"
            val level = (commandMap["level"] as? Number)?.toInt() ?: 0
            val timestampObj = commandMap["timestamp"] as? Timestamp
            val timestamp = timestampObj?.seconds ?: 0L

            if (timestamp > lastExecutedCommandTimestamp) {
                lastExecutedCommandTimestamp = timestamp
                executeVolumeCommand(stream, level, token)
            }
        }

        // 2. Process Screen Time Update
        val screenTimeMap = data["screenTime"] as? Map<*, *>
        if (screenTimeMap != null) {
            val remaining = (screenTimeMap["totalRemainingMinutes"] as? Number)?.toInt() ?: -1
            val limit = (screenTimeMap["totalLimitMinutes"] as? Number)?.toInt() ?: 120
            val appUsagesJsonStr = screenTimeMap["appUsages"] as? String ?: "[]"

            if (remaining >= 0) {
                updateScreenTimeData(remaining, limit, appUsagesJsonStr)
            }
        }

        // 3. Process Time Coins State
        val timeBankEnabled = data["timeBankEnabled"] as? Boolean ?: false
        val timeBankChildVisible = data["timeBankChildVisible"] as? Boolean ?: false
        val timeBankBalance = (data["timeBankBalance"] as? Number)?.toInt() ?: 0

        serviceScope.launch {
            val repoState = com.familylink.buddy.child.data.TimeBankState(
                isEnabled = timeBankEnabled,
                isChildVisible = timeBankChildVisible,
                balance = timeBankBalance
            )
            repository.updateTimeBankState(repoState)
            FamilyBuddyWidget().updateAll(applicationContext)
        }

        // 4. Process Coin Award
        val coinAwardMap = data["coinAward"] as? Map<*, *>
        if (coinAwardMap != null) {
            val amount = (coinAwardMap["amount"] as? Number)?.toInt() ?: 0
            val description = coinAwardMap["description"] as? String ?: ""
            val emoji = coinAwardMap["emoji"] as? String ?: "⏳"
            val timestampObj = coinAwardMap["timestamp"] as? Timestamp
            val timestamp = timestampObj?.seconds ?: 0L

            if (timestamp > lastExecutedCoinAwardTimestamp) {
                lastExecutedCoinAwardTimestamp = timestamp
                triggerCoinAwardFeedback(amount, description, emoji)
            }
        }

        // 5. Process Walkie-Talkie Signaling Session Launch
        val commsSessionId = data["activeCommsSessionId"] as? String
        val commsTimestampObj = data["activeCommsSessionTimestamp"] as? Timestamp
        val commsTimestamp = commsTimestampObj?.seconds ?: 0L

        if (commsSessionId != null && commsTimestamp > lastExecutedCommsSessionTimestamp) {
            lastExecutedCommsSessionTimestamp = commsTimestamp
            try {
                val intent = Intent(this, CommsActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra("action", "RECEIVE")
                    putExtra("sessionId", commsSessionId)
                }
                
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val builder = NotificationCompat.Builder(this, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                    .setContentTitle("Walkie-Talkie Anruf")
                    .setContentText("Eingehender Sprachchat von Elternteil")
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setFullScreenIntent(pendingIntent, true)
                    .setAutoCancel(true)

                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(9005, builder.build())

                try {
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.w(TAG, "Direct background startActivity failed, relying on fullScreenIntent notification: ${e.message}")
                }
                Log.d(TAG, "Launched CommsActivity overlay signaling session $commsSessionId via fullScreenIntent")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch CommsActivity from background service", e)
            }
        }
    }

    private fun triggerCoinAwardFeedback(amount: Int, description: String, emoji: String) {
        val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val isInteractive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            powerManager.isInteractive
        } else {
            @Suppress("DEPRECATION")
            powerManager.isScreenOn
        }

        if (isInteractive) {
            val intent = Intent(ACTION_COIN_AWARD).apply {
                putExtra("amount", amount)
                putExtra("description", description)
                putExtra("emoji", emoji)
            }
            sendBroadcast(intent)
        }
    }

    private fun executeVolumeCommand(stream: String, level: Int, token: String) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (stream != "GET_VOLUME") {
            val systemStream = when (stream) {
                "MEDIA" -> AudioManager.STREAM_MUSIC
                "RINGTONE" -> AudioManager.STREAM_RING
                "ALARM" -> AudioManager.STREAM_ALARM
                "ALL" -> -1
                else -> AudioManager.STREAM_MUSIC
            }

            if (systemStream == -1) {
                setStreamVolume(audioManager, AudioManager.STREAM_MUSIC, level)
                setStreamVolume(audioManager, AudioManager.STREAM_RING, level)
                setStreamVolume(audioManager, AudioManager.STREAM_ALARM, level)
            } else {
                setStreamVolume(audioManager, systemStream, level)
            }

            // Send transparency system notification inside the child service
            val notifyManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notif = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Lautstärke geändert")
                .setContentText("Lautstärke wurde von einem Elternteil geändert")
                .setSmallIcon(android.R.drawable.ic_lock_silent_mode)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            notifyManager.notify(9002, notif)
        }

        // Write back volume report
        val report = hashMapOf(
            "mediaVolume" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
            "ringtoneVolume" to audioManager.getStreamVolume(AudioManager.STREAM_RING),
            "alarmVolume" to audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
            "maxMediaVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            "maxRingtoneVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_RING),
            "maxAlarmVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        )
        try {
            val db = FirebaseFirestore.getInstance()
            db.collection("pairings").document(token).update("volumeReport", report)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update volume report in Firestore", e)
        }

        // Also update local DataStore state to refresh Child App UI
        val currentMedia = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val currentRing = audioManager.getStreamVolume(AudioManager.STREAM_RING)
        val currentAlarm = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val maxMedia = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val maxRing = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)
        val maxAlarm = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)

        val localState = VolumeState(
            mediaVolume = currentMedia,
            ringtoneVolume = currentRing,
            alarmVolume = currentAlarm,
            maxMediaVolume = maxMedia,
            maxRingtoneVolume = maxRing,
            maxAlarmVolume = maxAlarm,
            isMuted = currentMedia == 0,
            deviceToken = token
        )
        serviceScope.launch {
            repository.updateVolumeState(localState)
            Log.d(TAG, "Updated local repository volumeState from Firestore command: $currentMedia/$maxMedia")
        }
    }

    private fun setStreamVolume(audioManager: AudioManager, stream: Int, level: Int) {
        try {
            val max = audioManager.getStreamMaxVolume(stream)
            val clamped = level.coerceIn(0, max)
            audioManager.setStreamVolume(stream, clamped, AudioManager.FLAG_SHOW_UI)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set volume for stream $stream: ${e.message}", e)
        }
    }

    private fun updateScreenTimeData(remaining: Int, limit: Int, appUsagesJsonStr: String) {
        val appUsages = mutableListOf<AppUsage>()
        try {
            val jsonArray = org.json.JSONArray(appUsagesJsonStr)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                appUsages.add(
                    AppUsage(
                        packageName = obj.getString("packageName"),
                        appName = obj.getString("appName"),
                        usedMinutes = obj.getInt("usedMinutes"),
                        limitMinutes = obj.getInt("limitMinutes")
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing appUsages in direct update", e)
        }

        val updatedData = FamilyTimeData(
            totalRemainingMinutes = remaining,
            totalLimitMinutes = limit,
            lastUpdatedMillis = System.currentTimeMillis(),
            appUsages = appUsages
        )

        serviceScope.launch {
            repository.updateFamilyTimeData(updatedData)
            FamilyBuddyWidget().updateAll(applicationContext)
            Log.d(TAG, "Direct sync update applied: $remaining mins remaining")
        }
    }
}
