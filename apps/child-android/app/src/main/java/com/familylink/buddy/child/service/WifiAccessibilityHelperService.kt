package com.familylink.buddy.child.service

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import com.familylink.buddy.child.R
import com.familylink.buddy.child.data.AppInterceptionResult
import com.familylink.buddy.child.data.AppLimitsManager
import com.familylink.buddy.child.data.AppRules
import com.familylink.buddy.child.data.AntiTamperDetector
import com.familylink.buddy.child.data.ChatMessageRecord
import com.familylink.buddy.child.data.CommunicationDatabaseHelper
import com.familylink.buddy.child.data.FamilyTimeRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

/**
 * Automated Wi-Fi toggling service using Android AccessibilityService.
 * Controls the physical Wi-Fi switch via Settings.Panel.ACTION_WIFI to toggle
 * Wi-Fi on or off during bedtime schedules without requiring root or system signature.
 */
class WifiAccessibilityHelperService : AccessibilityService() {

    private val tickerHandler = Handler(Looper.getMainLooper())
    private var tickerCounter = 0L
    private var lastToastTime = 0L
    private var lastToastMessage: String? = null

    // Outgoing chat composition tracking
    private var lastComposedChatText: String? = null
    private var lastComposedChatPackage: String? = null
    private var lastComposedChatTime: Long = 0L

    // Real-time app opening recording
    private var lastRecordedAppPackage: String? = null
    private var lastRecordedAppTime: Long = 0L

    private val tickerRunnable = object : Runnable {
        override fun run() {
            onLimitsTimerTick()
            tickerHandler.postDelayed(this, 1000L)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "WifiAccessibilityHelperService connected")
        val repository = FamilyTimeRepository(applicationContext)
        LocalHttpServer.startServer(applicationContext, repository)
        AppLimitsManager.getInstance(this)
        startLimitsTicker()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val schedule = repository.bedtimeSchedule.first()
                BedtimeScheduleReceiver.scheduleNextAlarms(applicationContext, schedule)
            } catch (e: Exception) {
                Log.e(TAG, "Error scheduling bedtime alarms on service connected", e)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopLimitsTicker()
        try {
            val prefs = getSharedPreferences(AppLimitsManager.PREFS_NAME, Context.MODE_PRIVATE)
            AppLimitsManager.getInstance(this).saveToPreferences(prefs)
        } catch (e: Exception) {
            Log.e(TAG, "Failed saving app limits preferences on destroy", e)
        }
        if (instance == this) {
            instance = null
        }
        Log.i(TAG, "WifiAccessibilityHelperService destroyed")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Media playback detection via active notifications
        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val parcelable = event.parcelableData
            if (parcelable is android.app.Notification) {
                val extras = parcelable.extras
                val title = extras?.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString()
                val text = extras?.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString()
                val subText = extras?.getCharSequence(android.app.Notification.EXTRA_SUB_TEXT)?.toString()
                val artist = if (!text.isNullOrBlank()) text else subText
                val eventPkg = event.packageName?.toString()
                if (!title.isNullOrBlank() || !artist.isNullOrBlank()) {
                    com.familylink.buddy.child.data.AudioPlaybackManager.updateMediaInfo(title, artist, eventPkg)
                }
            }
        }

        val pkg = event.packageName?.toString()
        if (!pkg.isNullOrBlank()) {
            if (ChatNotificationListenerService.SUPPORTED_PACKAGES.contains(pkg)) {
                handleMessagingAccessibilityEvent(event, pkg)
            }

            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || latestPackageName == null) {
                latestPackageName = pkg
            }

            // Real-time app opening recording
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                if (pkg != "com.android.systemui" &&
                    pkg != packageName &&
                    !isLauncherPackage(this, pkg) &&
                    !com.familylink.buddy.child.data.InstalledAppsManager.isAllowedExcludedApp(this, pkg)
                ) {
                    val now = System.currentTimeMillis()
                    if (pkg != lastRecordedAppPackage || (now - lastRecordedAppTime > 3000L)) {
                        val label = getAppLabel(pkg)
                        CommunicationDatabaseHelper.getInstance(this).insertAppOpening(pkg, label, now)
                        lastRecordedAppPackage = pkg
                        lastRecordedAppTime = now
                    }
                }
            }

            // Anti-tamper check: prevent child from disabling accessibility or uninstalling
            if (AntiTamperDetector.isSettingsApp(pkg)) {
                val repository = FamilyTimeRepository(applicationContext)
                val pinConfigured = try {
                    repository.isPinConfiguredSync()
                } catch (e: Exception) {
                    false
                }
                val isUnlocked = isParentUnlocked()

                val texts = mutableListOf<String>()
                event.text.forEach { if (it.isNotBlank()) texts.add(it.toString()) }
                rootInActiveWindow?.let { root ->
                    collectNodeTexts(root, texts, maxDepth = 4)
                }
                val cls = event.className?.toString()

                if (AntiTamperDetector.shouldEnforceTamperProtection(pkg, cls, texts, pinConfigured, isUnlocked)) {
                    Log.w(TAG, "Anti-tamper: Accessibility settings access prevented for package $pkg ($cls)")
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    showInterceptionToast(getString(R.string.pin_required_toast))
                    return
                }
            }

            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
                pkg == com.familylink.buddy.child.data.InstalledAppsManager.GOOGLE_SEARCH_PACKAGE) {
                val interception = checkAndInterceptPackage(pkg)
                if (interception is AppInterceptionResult.BlockedBlacklist ||
                    interception is AppInterceptionResult.BlockedCategoryLimit) {
                    return
                }
            }
        }

        if (pendingTargetState == TARGET_STATE_NONE) return

        // Auto-expire pending requests older than 15 seconds
        if (System.currentTimeMillis() - pendingRequestTimestamp > 15_000) {
            Log.w(TAG, "Pending Wi-Fi toggle request timed out; resetting state.")
            pendingTargetState = TARGET_STATE_NONE
            return
        }

        val rootNode = rootInActiveWindow ?: return

        try {
            val switchNode = findWifiSwitchNode(rootNode)
            if (switchNode != null) {
                val isChecked = switchNode.isChecked
                Log.d(TAG, "Found Wi-Fi switch node: isChecked=$isChecked, targetState=$pendingTargetState")

                when (pendingTargetState) {
                    TARGET_STATE_OFF -> {
                        if (isChecked) {
                            Log.i(TAG, "Toggling Wi-Fi OFF...")
                            val success = switchNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            if (!success && switchNode.parent?.isClickable == true) {
                                switchNode.parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            }
                        } else {
                            Log.i(TAG, "Wi-Fi is already OFF.")
                        }
                        pendingTargetState = TARGET_STATE_NONE
                        // Dismiss the panel
                        performGlobalAction(GLOBAL_ACTION_BACK)
                    }

                    TARGET_STATE_ON -> {
                        if (!isChecked) {
                            Log.i(TAG, "Toggling Wi-Fi ON...")
                            val success = switchNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            if (!success && switchNode.parent?.isClickable == true) {
                                switchNode.parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            }
                        } else {
                            Log.i(TAG, "Wi-Fi is already ON.")
                        }
                        pendingTargetState = TARGET_STATE_NONE
                        // Dismiss the panel
                        performGlobalAction(GLOBAL_ACTION_BACK)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling accessibility event for Wi-Fi toggle", e)
        }
    }

    private fun findWifiSwitchNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // 1. First pass: look for a checkable/switch node associated with Wi-Fi / WLAN / Internet
        val candidate = searchNode(root) { node ->
            val isSwitchOrCheckable = node.isCheckable ||
                    node.className?.toString()?.contains("Switch", ignoreCase = true) == true ||
                    node.className?.toString()?.contains("CompoundButton", ignoreCase = true) == true

            if (!isSwitchOrCheckable) return@searchNode false

            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            val parentText = node.parent?.text?.toString() ?: ""
            val parentDesc = node.parent?.contentDescription?.toString() ?: ""

            matchesWifiKeyword(text) || matchesWifiKeyword(desc) ||
                    matchesWifiKeyword(parentText) || matchesWifiKeyword(parentDesc)
        }

        if (candidate != null) return candidate

        // 2. Second pass: in ACTION_WIFI panel, the main toggle is usually the only Switch/CompoundButton
        return searchNode(root) { node ->
            node.isCheckable ||
                    node.className?.toString()?.contains("Switch", ignoreCase = true) == true ||
                    node.className?.toString()?.contains("CompoundButton", ignoreCase = true) == true
        }
    }

    private fun searchNode(
        node: AccessibilityNodeInfo?,
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (node == null) return null
        if (predicate(node)) return node

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = searchNode(child, predicate)
            if (found != null) return found
        }
        return null
    }

    private fun matchesWifiKeyword(str: String): Boolean {
        return str.contains("Wi-Fi", ignoreCase = true) ||
                str.contains("WLAN", ignoreCase = true) ||
                str.contains("Wifi", ignoreCase = true) ||
                str.contains("Internet", ignoreCase = true)
    }

    private fun collectNodeTexts(node: AccessibilityNodeInfo?, list: MutableList<String>, maxDepth: Int) {
        if (node == null || maxDepth <= 0 || list.size >= 25) return
        node.text?.toString()?.takeIf { it.isNotBlank() }?.let { list.add(it) }
        node.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { list.add(it) }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectNodeTexts(child, list, maxDepth - 1)
            if (list.size >= 25) break
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "WifiAccessibilityHelperService interrupted")
        pendingTargetState = TARGET_STATE_NONE
    }

    fun getForegroundAppInfo(context: Context = this): Pair<String, String> =
        Companion.getForegroundAppInfo(context)

    fun closeCurrentApp(context: Context = this): Boolean =
        Companion.closeCurrentApp(context)

    fun lockScreen(context: Context = this): Boolean =
        Companion.lockScreen(context)

    fun checkAndInterceptPackage(pkg: String): AppInterceptionResult {
        if (pkg.isBlank()) return AppInterceptionResult.None

        val manager = AppLimitsManager.getInstance(this)

        // Always check blacklist first! Ensure com.google.android.googlequicksearchbox
        // or any blacklisted package is intercepted immediately.
        val isBlacklisted = manager.getRules().blacklistedPackages.contains(pkg)
        if (isBlacklisted) {
            val appLabel = getAppLabel(pkg)
            val result = manager.onPackageChanged(pkg, appLabel)
            if (result is AppInterceptionResult.BlockedBlacklist) {
                Log.w(TAG, "Blocking blacklisted app: $pkg ($appLabel)")
                performGlobalAction(GLOBAL_ACTION_HOME)
                showInterceptionToast(getString(R.string.app_blocked_toast, appLabel))
                return result
            }
        }

        // Ignore launcher, our own child app, and System UI
        if (isLauncherPackage(this, pkg) || pkg == packageName || pkg == "com.android.systemui") {
            AppLimitsManager.getInstance(this).onSystemOrLauncherActive(pkg)
            return AppInterceptionResult.None
        }

        val appLabel = getAppLabel(pkg)
        val result = manager.onPackageChanged(pkg, appLabel)

        when (result) {
            is AppInterceptionResult.BlockedBlacklist -> {
                Log.w(TAG, "Blocking blacklisted app: $pkg ($appLabel)")
                performGlobalAction(GLOBAL_ACTION_HOME)
                showInterceptionToast(getString(R.string.app_blocked_toast, appLabel))
            }
            is AppInterceptionResult.BlockedCategoryLimit -> {
                Log.w(TAG, "Blocking category-limited app: $pkg ($appLabel) - Category: ${result.categoryName}")
                performGlobalAction(GLOBAL_ACTION_HOME)
                showInterceptionToast(getString(R.string.category_limit_toast, result.categoryName))
            }
            is AppInterceptionResult.Allowed -> {
                Log.d(TAG, "App allowed: $pkg (activeCategory=${result.activeCategoryId})")
            }
            AppInterceptionResult.None -> {}
        }
        return result
    }

    private fun getAppLabel(pkg: String): String {
        return try {
            val pm = packageManager
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(pkg, 0)
            }
            val label = pm.getApplicationLabel(appInfo).toString()
            if (label.isNotBlank()) label else pkg
        } catch (e: Exception) {
            pkg
        }
    }

    private fun showInterceptionToast(message: String) {
        val now = System.currentTimeMillis()
        if (now - lastToastTime < 1500L && lastToastMessage == message) {
            return
        }
        lastToastTime = now
        lastToastMessage = message

        Handler(Looper.getMainLooper()).post {
            try {
                Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to display toast: $message", e)
            }
        }
    }

    private fun startLimitsTicker() {
        tickerHandler.removeCallbacks(tickerRunnable)
        tickerHandler.postDelayed(tickerRunnable, 1000L)
    }

    private fun stopLimitsTicker() {
        tickerHandler.removeCallbacks(tickerRunnable)
    }

    private fun onLimitsTimerTick() {
        tickerCounter++
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isInteractive = powerManager?.isInteractive ?: true
        val manager = AppLimitsManager.getInstance(this)

        val result = manager.onTick(isInteractive)
        if (result is AppInterceptionResult.BlockedCategoryLimit) {
            Log.i(TAG, "Limit reached during active foreground usage for category ${result.categoryName}")
            performGlobalAction(GLOBAL_ACTION_HOME)
            showInterceptionToast(getString(R.string.category_limit_toast, result.categoryName))
        }

        if (tickerCounter % 30 == 0L) {
            try {
                val prefs = getSharedPreferences(AppLimitsManager.PREFS_NAME, Context.MODE_PRIVATE)
                manager.saveToPreferences(prefs)
            } catch (e: Exception) {
                Log.e(TAG, "Error during periodic limits persistence", e)
            }
        }
    }

    private fun handleMessagingAccessibilityEvent(event: AccessibilityEvent, pkg: String) {
        try {
            // Track text being composed in EditText
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED) {
                val enteredText = event.text.joinToString(" ").trim()
                if (enteredText.isNotEmpty()) {
                    lastComposedChatText = enteredText
                    lastComposedChatPackage = pkg
                    lastComposedChatTime = System.currentTimeMillis()
                }
            }

            // Also check current active EditText if text is blank but user is interacting
            if (lastComposedChatText.isNullOrBlank() && event.eventType == AccessibilityEvent.TYPE_VIEW_FOCUSED) {
                rootInActiveWindow?.let { root ->
                    val editNode = searchNode(root) { node ->
                        node.className?.toString()?.contains("EditText", ignoreCase = true) == true &&
                                !node.text.isNullOrBlank()
                    }
                    editNode?.text?.toString()?.trim()?.let {
                        if (it.isNotEmpty()) {
                            lastComposedChatText = it
                            lastComposedChatPackage = pkg
                            lastComposedChatTime = System.currentTimeMillis()
                        }
                    }
                }
            }

            // Check if Send button was clicked
            if (isSendAction(event)) {
                val textToSend = lastComposedChatText
                val recentTime = System.currentTimeMillis() - lastComposedChatTime < 15_000L
                if (!textToSend.isNullOrBlank() && recentTime) {
                    val root = rootInActiveWindow
                    val chatTitle = findConversationTitle(root) ?: "Active Chat"
                    val appName = ChatNotificationListenerService.getFriendlyAppName(pkg)
                    val recordId = "chat_out_${pkg}_${System.currentTimeMillis()}_${(textToSend.hashCode() and 0x7FFFFFFF)}"

                    val record = ChatMessageRecord(
                        id = recordId,
                        appPackage = pkg,
                        appName = appName,
                        senderOrChat = chatTitle,
                        text = textToSend,
                        isOutgoing = true,
                        timestamp = System.currentTimeMillis()
                    )

                    Log.d(TAG, "Captured outgoing chat message in $appName to $chatTitle: ${textToSend.take(30)}...")
                    CommunicationDatabaseHelper.getInstance(applicationContext).insertChatMessage(record)
                    lastComposedChatText = null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling messaging accessibility event: ${e.message}", e)
        }
    }

    private fun isSendAction(event: AccessibilityEvent): Boolean {
        if (event.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return false
        val desc = event.contentDescription?.toString()?.lowercase() ?: ""
        val text = event.text.joinToString(" ").lowercase()
        val isSendDesc = desc.contains("send") || desc.contains("senden") || text.contains("send") || text.contains("senden")
        if (isSendDesc) return true

        val source = try { event.source } catch (_: Exception) { null }
        val resId = source?.viewIdResourceName?.lowercase() ?: ""
        if (resId.contains("send")) return true

        return false
    }

    private fun findConversationTitle(root: AccessibilityNodeInfo?): String? {
        if (root == null) return null
        val found = searchNode(root) { node ->
            val resId = node.viewIdResourceName?.lowercase() ?: ""
            val isHeader = resId.contains("conversation_title") ||
                    resId.contains("toolbar") ||
                    resId.contains("action_bar_title") ||
                    resId.contains("contact_name") ||
                    resId.contains("chat_title")
            isHeader && !node.text.isNullOrBlank()
        }
        return found?.text?.toString()?.trim()
    }

    companion object {
        private const val TAG = "WifiAccessibility"

        @Volatile
        var instance: WifiAccessibilityHelperService? = null

        @Volatile
        var latestPackageName: String? = null

        @Volatile
        var childToken: String? = null

        @Volatile
        private var parentUnlockExpiryTime: Long = 0L

        fun isParentUnlocked(): Boolean {
            return System.currentTimeMillis() < parentUnlockExpiryTime
        }

        fun unlockAntiTamper(durationMillis: Long = 3 * 60 * 1000L) {
            parentUnlockExpiryTime = System.currentTimeMillis() + durationMillis
            Log.i(TAG, "Anti-tamper temporarily unlocked for ${durationMillis / 1000}s")
        }

        fun lockAntiTamper() {
            parentUnlockExpiryTime = 0L
            Log.i(TAG, "Anti-tamper locked")
        }

        fun updateAppRules(context: Context, rules: AppRules) {
            val manager = AppLimitsManager.getInstance(context)
            manager.updateRules(rules)
            try {
                val prefs = context.getSharedPreferences(AppLimitsManager.PREFS_NAME, Context.MODE_PRIVATE)
                manager.saveToPreferences(prefs)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving rules to preferences", e)
            }

            // Immediately check current foreground app
            checkAndInterceptForeground(context)
        }

        fun checkAndInterceptForeground(@Suppress("UNUSED_PARAMETER") context: Context? = null) {
            val service = instance
            if (service != null) {
                val currentPkg = latestPackageName ?: service.rootInActiveWindow?.packageName?.toString()
                if (!currentPkg.isNullOrBlank()) {
                    service.checkAndInterceptPackage(currentPkg)
                }
            }
        }

        fun addBonusMinutes(context: Context, categoryId: String, extraMinutes: Int) {
            val manager = AppLimitsManager.getInstance(context)
            manager.addBonusMinutes(categoryId, extraMinutes)
            try {
                val prefs = context.getSharedPreferences(AppLimitsManager.PREFS_NAME, Context.MODE_PRIVATE)
                manager.saveToPreferences(prefs)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving bonus minutes to preferences", e)
            }

            checkAndInterceptForeground(context)
        }

        const val TARGET_STATE_NONE = 0
        const val TARGET_STATE_OFF = 1
        const val TARGET_STATE_ON = 2

        @Volatile
        var pendingTargetState: Int = TARGET_STATE_NONE

        @Volatile
        var pendingRequestTimestamp: Long = 0L

        /**
         * Detects the currently active foreground application's label and package name.
         */
        fun getForegroundAppInfo(context: Context): Pair<String, String> {
            val service = instance
            val rawPackage = service?.rootInActiveWindow?.packageName?.toString()
                ?.takeIf { it.isNotBlank() }
                ?: latestPackageName
                ?: context.packageName

            val pm = context.packageManager

            if (isLauncherPackage(context, rawPackage)) {
                return Pair(context.getString(R.string.label_home_screen), rawPackage)
            }
            if (rawPackage == context.packageName) {
                return Pair("FamilyLink Buddy", rawPackage)
            }

            val label = try {
                val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getApplicationInfo(rawPackage, PackageManager.ApplicationInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getApplicationInfo(rawPackage, 0)
                }
                pm.getApplicationLabel(appInfo).toString()
            } catch (e: Exception) {
                when {
                    rawPackage.contains("launcher", ignoreCase = true) ||
                    rawPackage.contains("nexuslauncher", ignoreCase = true) ||
                    rawPackage.contains("trebuchet", ignoreCase = true) ||
                    rawPackage.contains("quickstep", ignoreCase = true) -> context.getString(R.string.label_home_screen)
                    rawPackage.contains("systemui", ignoreCase = true) -> "System UI"
                    rawPackage == context.packageName -> "FamilyLink Buddy"
                    else -> rawPackage
                }
            }

            val finalLabel = if (label.isNotBlank()) label else rawPackage
            return Pair(finalLabel, rawPackage)
        }

        fun isLauncherPackage(context: Context, packageName: String): Boolean {
            if (packageName.isBlank()) return false
            if (packageName == com.familylink.buddy.child.data.InstalledAppsManager.GOOGLE_SEARCH_PACKAGE) {
                return false
            }
            if (packageName.contains("launcher", ignoreCase = true) ||
                packageName.contains("nexuslauncher", ignoreCase = true) ||
                packageName.contains("trebuchet", ignoreCase = true) ||
                packageName.contains("quickstep", ignoreCase = true)) {
                return true
            }
            return try {
                val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                val resolveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.packageManager.resolveActivity(
                        homeIntent,
                        PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                    )
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
                }
                resolveInfo?.activityInfo?.packageName == packageName
            } catch (e: Exception) {
                false
            }
        }

        /**
         * Closes the current open app by pressing HOME via accessibility action and Intent,
         * and displaying a notification/toast to the child.
         */
        fun closeCurrentApp(context: Context): Boolean {
            var executed = false
            val service = instance
            if (service != null) {
                val actionSuccess = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
                if (actionSuccess) {
                    executed = true
                }
            }

            try {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(homeIntent)
                executed = true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to dispatch home intent fallback in closeCurrentApp", e)
            }

            try {
                Handler(Looper.getMainLooper()).post {
                    try {
                        Toast.makeText(
                            context.applicationContext,
                            context.getString(R.string.toast_app_closed_by_parent),
                            Toast.LENGTH_SHORT
                        ).show()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to display toast notification", e)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to post toast to main looper", e)
            }

            return executed
        }

        /**
         * Locks the screen / turns off the display using AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN
         * and displays a toast notification to the child.
         */
        fun lockScreen(context: Context): Boolean {
            var executed = false
            val service = instance
            if (service != null) {
                val actionSuccess = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                if (actionSuccess) {
                    executed = true
                    Log.i(TAG, "GLOBAL_ACTION_LOCK_SCREEN executed successfully")
                } else {
                    Log.w(TAG, "performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN) returned false")
                }
            } else {
                Log.w(TAG, "lockScreen: AccessibilityService instance is null")
            }

            try {
                Handler(Looper.getMainLooper()).post {
                    try {
                        Toast.makeText(
                            context.applicationContext,
                            context.getString(R.string.toast_screen_locked_by_parent),
                            Toast.LENGTH_SHORT
                        ).show()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to display lock screen toast notification", e)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to post lock screen toast to main looper", e)
            }

            return executed
        }

        /**
         * Captures a screenshot using Android AccessibilityService API (API 30+).
         */
        fun captureScreenshot(
            callback: (base64Jpeg: String?, foregroundApp: String, foregroundPackage: String, error: String?) -> Unit
        ) {
            val service = instance
            if (service == null) {
                callback(null, "Unbekannt", "", "Accessibility Service is not connected")
                return
            }

            val (foregroundApp, foregroundPackage) = getForegroundAppInfo(service)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    service.takeScreenshot(
                        Display.DEFAULT_DISPLAY,
                        service.mainExecutor,
                        object : TakeScreenshotCallback {
                            override fun onSuccess(screenshotResult: ScreenshotResult) {
                                try {
                                    val hardwareBuffer = screenshotResult.hardwareBuffer
                                    val colorSpace = screenshotResult.colorSpace
                                    val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                                    if (bitmap == null) {
                                        hardwareBuffer.close()
                                        callback(null, foregroundApp, foregroundPackage, "Failed to wrap HardwareBuffer to Bitmap")
                                        return
                                    }

                                    val softwareBitmap = try {
                                        bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                    } finally {
                                        hardwareBuffer.close()
                                        bitmap.recycle()
                                    }

                                    if (softwareBitmap == null) {
                                        callback(null, foregroundApp, foregroundPackage, "Failed to copy hardware buffer to software Bitmap")
                                        return
                                    }

                                    val finalBitmap = if (softwareBitmap.width > 1280) {
                                        val ratio = 1280f / softwareBitmap.width
                                        val targetHeight = (softwareBitmap.height * ratio).toInt()
                                        val scaled = Bitmap.createScaledBitmap(softwareBitmap, 1280, targetHeight, true)
                                        if (scaled != softwareBitmap) {
                                            softwareBitmap.recycle()
                                        }
                                        scaled
                                    } else {
                                        softwareBitmap
                                    }

                                    val outputStream = ByteArrayOutputStream()
                                    finalBitmap.compress(Bitmap.CompressFormat.JPEG, 75, outputStream)
                                    finalBitmap.recycle()
                                    val bytes = outputStream.toByteArray()
                                    val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                    callback(base64, foregroundApp, foregroundPackage, null)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Error processing screenshot bitmap", e)
                                    callback(null, foregroundApp, foregroundPackage, "Error processing screenshot: ${e.message}")
                                }
                            }

                            override fun onFailure(errorCode: Int) {
                                Log.e(TAG, "takeScreenshot failed with errorCode: $errorCode")
                                callback(null, foregroundApp, foregroundPackage, "Take screenshot failed with error code: $errorCode")
                            }
                        }
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Exception calling takeScreenshot", e)
                    callback(null, foregroundApp, foregroundPackage, "Exception calling takeScreenshot: ${e.message}")
                }
            } else {
                callback(null, foregroundApp, foregroundPackage, "Android 11+ required for background accessibility screenshot")
            }
        }

        /**
         * Requests toggling physical Wi-Fi state via Settings Panel and Accessibility Service.
         */
        fun requestToggle(context: Context, turnOn: Boolean) {
            pendingTargetState = if (turnOn) TARGET_STATE_ON else TARGET_STATE_OFF
            pendingRequestTimestamp = System.currentTimeMillis()
            Log.i(TAG, "Requesting Wi-Fi toggle: turnOn=$turnOn (targetState=$pendingTargetState)")

            try {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    Intent(Settings.Panel.ACTION_WIFI).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                } else {
                    Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch Wi-Fi Settings Panel", e)
                // Fallback to general Wi-Fi settings
                try {
                    val fallbackIntent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(fallbackIntent)
                } catch (ex: Exception) {
                    Log.e(TAG, "Failed to launch fallback Wi-Fi settings", ex)
                }
            }
        }
    }
}
