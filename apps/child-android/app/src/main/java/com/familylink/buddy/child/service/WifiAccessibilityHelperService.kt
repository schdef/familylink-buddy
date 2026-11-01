package com.familylink.buddy.child.service

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.io.ByteArrayOutputStream

/**
 * Automated Wi-Fi toggling service using Android AccessibilityService.
 * Controls the physical Wi-Fi switch via Settings.Panel.ACTION_WIFI to toggle
 * Wi-Fi on or off during bedtime schedules without requiring root or system signature.
 */
class WifiAccessibilityHelperService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "WifiAccessibilityHelperService connected")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
        Log.i(TAG, "WifiAccessibilityHelperService destroyed")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString()
        if (!pkg.isNullOrBlank()) {
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || latestPackageName == null) {
                latestPackageName = pkg
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

    override fun onInterrupt() {
        Log.w(TAG, "WifiAccessibilityHelperService interrupted")
        pendingTargetState = TARGET_STATE_NONE
    }

    fun getForegroundAppInfo(context: Context = this): Pair<String, String> =
        Companion.getForegroundAppInfo(context)

    fun closeCurrentApp(context: Context = this): Boolean =
        Companion.closeCurrentApp(context)

    companion object {
        private const val TAG = "WifiAccessibility"

        @Volatile
        var instance: WifiAccessibilityHelperService? = null

        @Volatile
        var latestPackageName: String? = null

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
                return Pair("Startbildschirm", rawPackage)
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
                    rawPackage.contains("quickstep", ignoreCase = true) -> "Startbildschirm"
                    rawPackage.contains("systemui", ignoreCase = true) -> "System UI"
                    rawPackage == context.packageName -> "FamilyLink Buddy"
                    else -> rawPackage
                }
            }

            val finalLabel = if (label.isNotBlank()) label else rawPackage
            return Pair(finalLabel, rawPackage)
        }

        private fun isLauncherPackage(context: Context, packageName: String): Boolean {
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
                            "App wurde von Elternteil beendet",
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
