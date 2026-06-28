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
import java.util.Locale

class WidgetUpdateService : Service() {

    companion object {
        private const val TAG = "WidgetUpdateService"
        private const val CHANNEL_ID = "background_keep_alive"
        private const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_MOCK_ROCKET = "ACTION_MOCK_ROCKET"
    }

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var repository: FamilyTimeRepository
    private var tickerJob: Job? = null
    private var dbObserverJob: Job? = null
    private var isScreenOn = true
    private var localHttpServer: LocalHttpServer? = null

    // Overlay state variables
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var isOverlayShown = false
    private var isMockRocketRunning = false
    private var overlaySecondsRemaining = 180
    private var overlaySecondsRemainingFloat = 180f
    private var overlayTickerJob: Job? = null
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
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)
        hideOverlay()
        firestoreListenerRegistration?.remove()
        firestoreListenerRegistration = null
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
        val lockedApp = data.appUsages.firstOrNull { it.remainingMinutes <= 0 }

        if ((remaining <= 3 && remaining > 0) || lockedApp != null) {
            if (isMockRocketRunning) {
                if (remaining == 1) {
                    // Ignore background DB checks while mock rocket simulation is explicitly active
                    return
                } else {
                    isMockRocketRunning = false
                }
            }
            
            if (lockedApp != null) {
                overlaySecondsRemaining = 0
            } else {
                overlaySecondsRemaining = remaining * 60
            }

            if (!isOverlayShown) {
                showOverlay()
            } else {
                if (lockedApp == null) {
                    val expectedSeconds = remaining * 60
                    if (Math.abs(overlaySecondsRemaining - expectedSeconds) > 15) {
                        overlaySecondsRemaining = expectedSeconds
                    }
                }
            }
        } else {
            isMockRocketRunning = false
            hideOverlay()
        }
    }

    private fun triggerMockRocketLaunch() {
        isMockRocketRunning = true
        overlaySecondsRemaining = 30
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
            private var touchDownTime = 0L
            private var tapCount = 0
            private var lastTapTime = 0L

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = overlayParams?.x ?: 0
                        initialY = overlayParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        touchDownTime = System.currentTimeMillis()
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
                        val duration = System.currentTimeMillis() - touchDownTime
                        val dx = Math.abs(event.rawX - initialTouchX)
                        val dy = Math.abs(event.rawY - initialTouchY)
                        val density = resources.displayMetrics.density

                        // Consider it a tap if duration is short and drag movement is within 8dp bounds
                        if (duration < 250 && dx < 8 * density && dy < 8 * density) {
                            val now = System.currentTimeMillis()
                            if (now - lastTapTime < 500) {
                                tapCount++
                            } else {
                                tapCount = 1
                            }
                            lastTapTime = now

                            Log.d(TAG, "Overlay tapped: $tapCount/4")
                            if (tapCount >= 4) {
                                Log.d(TAG, "Overlay tapped 4 times: dismissing")
                                hideOverlay()
                            }
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
                // Fetch current DB details to check for active app locks
                val currentData = repository.familyTimeData.first()
                val lockedApp = currentData.appUsages.firstOrNull { it.remainingMinutes <= 0 }

                if (lockedApp != null) {
                    // App Lock State: Show app name reason and LOCK status
                    overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = getString(R.string.text_locked)
                    countdownLabel?.text = lockedApp.appName

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

                            countdownLabel?.text = "${getString(R.string.lock_reason_device)}: ${getString(R.string.rocket_preparing)}"

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

                            countdownLabel?.text = "${getString(R.string.lock_reason_device)}: ${getString(R.string.rocket_launching)}"

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

                            countdownLabel?.text = "${getString(R.string.lock_reason_device)}: ${getString(R.string.rocket_orbit)}"

                            val progress = (10f - t) / 10f // 0.0 to 1.0
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
                        countdownLabel?.text = getString(R.string.lock_reason_device)
                    }

                    if (t <= 0f) {
                        overlayView?.findViewById<TextView>(com.familylink.buddy.child.R.id.countdownText)?.text = "00:00"
                        // Keep the overlay visible for 5 seconds after countdown ends, then hide
                        delay(5000)
                        hideOverlay()
                        break
                    }
                    overlaySecondsRemainingFloat -= 0.05f
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

    private fun registerFirestoreListener(token: String) {
        firestoreListenerRegistration?.remove()
        try {
            if (com.familylink.buddy.child.BuildConfig.USE_EMULATOR) {
                try {
                    FirebaseFirestore.getInstance().useEmulator("10.0.2.2", 8080)
                } catch (e: IllegalStateException) {
                    // Already initialized
                }
            }
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
    }

    private fun setStreamVolume(audioManager: AudioManager, stream: Int, level: Int) {
        val max = audioManager.getStreamMaxVolume(stream)
        val clamped = level.coerceIn(0, max)
        audioManager.setStreamVolume(stream, clamped, AudioManager.FLAG_SHOW_UI)
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
