package com.familylink.buddy.child.service

import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import com.familylink.buddy.child.BuildConfig
import com.familylink.buddy.child.data.AppLimitsManager
import com.familylink.buddy.child.data.AppRules
import com.familylink.buddy.child.data.AudioPlaybackManager
import com.familylink.buddy.child.data.BedtimeSchedule
import com.familylink.buddy.child.data.CallLogManager
import com.familylink.buddy.child.data.CommunicationDatabaseHelper
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.data.InstalledAppsManager
import com.familylink.buddy.child.data.SilentCameraManager
import com.familylink.buddy.child.data.VolumeState
import com.familylink.buddy.child.data.toJsonArray
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.URLDecoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class LocalHttpServer(
    private val context: Context,
    private val repository: FamilyTimeRepository
) {
    companion object {
        private const val TAG = "LocalHttpServer"
        const val PORT = 8085
        @Volatile private var instance: LocalHttpServer? = null

        fun startServer(context: Context, repository: FamilyTimeRepository): LocalHttpServer {
            return instance?.also { if (!it.isRunning) it.start() } ?: synchronized(this) {
                instance?.also { if (!it.isRunning) it.start() } ?: LocalHttpServer(context.applicationContext, repository).also {
                    instance = it
                    it.start()
                }
            }
        }

        fun stopServer() {
            synchronized(this) {
                instance?.stop()
                instance = null
            }
        }

        fun getInstance(): LocalHttpServer? = instance
    }

    private var serverSocket: ServerSocket? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var isRunning = false
    private val scope = CoroutineScope(Dispatchers.IO)

    fun start() {
        if (isRunning) return
        isRunning = true

        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "FamilyLinkBuddy:HttpServerLock")?.apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.d(TAG, "Acquired WifiLock for LocalHttpServer")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire WifiLock", e)
        }

        Thread {
            try {
                serverSocket = ServerSocket().apply {
                    reuseAddress = true
                    bind(java.net.InetSocketAddress("0.0.0.0", PORT), 50)
                }
                Log.d(TAG, "Local developer HTTP server started on port $PORT")
                while (isRunning) {
                    val client = serverSocket?.accept() ?: break
                    Thread {
                        handleClient(client)
                    }.start()
                }
            } catch (e: SocketException) {
                if (isRunning) {
                    Log.e(TAG, "SocketException in server loop", e)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception in server loop", e)
            } finally {
                isRunning = false
            }
        }.start()
    }

    fun stop() {
        isRunning = false
        try {
            wifiLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            wifiLock = null
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing WifiLock", e)
        }
        try {
            serverSocket?.close()
            serverSocket = null
            Log.d(TAG, "Local developer HTTP server stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error closing server socket", e)
        }
    }

    private fun handleClient(client: Socket) {
        try {
            val rawInput = client.getInputStream()
            val writer = PrintWriter(client.getOutputStream())

            val firstLine = readLineFromStream(rawInput) ?: ""
            Log.d(TAG, "Received request: $firstLine")
            if (firstLine.isEmpty()) {
                client.close()
                return
            }

            // Read HTTP headers
            val headers = mutableMapOf<String, String>()
            while (true) {
                val headerLine = readLineFromStream(rawInput) ?: break
                if (headerLine.isEmpty()) break
                val colonIdx = headerLine.indexOf(':')
                if (colonIdx > 0) {
                    val key = headerLine.substring(0, colonIdx).trim().lowercase()
                    val value = headerLine.substring(colonIdx + 1).trim()
                    headers[key] = value
                }
            }

            val contentLength = headers["content-length"]?.toIntOrNull() ?: 0

            val parts = firstLine.split(" ")
            val method = parts.getOrNull(0) ?: "GET"
            val pathAndQuery = parts.getOrNull(1) ?: "/"
            val queryIdx = pathAndQuery.indexOf('?')
            val path = if (queryIdx >= 0) pathAndQuery.substring(0, queryIdx) else pathAndQuery
            val queryString = if (queryIdx >= 0) pathAndQuery.substring(queryIdx + 1) else ""

            val queryParams = queryString.split("&").filter { it.contains("=") }.associate {
                val kv = it.split("=", limit = 2)
                try {
                    URLDecoder.decode(kv[0], "UTF-8") to URLDecoder.decode(kv.getOrElse(1) { "" }, "UTF-8")
                } catch (e: Exception) {
                    kv[0] to kv.getOrElse(1) { "" }
                }
            }

            if (method.equals("OPTIONS", ignoreCase = true)) {
                sendHttpResponse(writer, 200, "OK", "")
                client.close()
                return
            }

            // Security token verification
            val pairingToken = repository.getOrCreateDeviceTokenSync()
            val incomingToken = headers["x-buddy-token"]
                ?: headers["authorization"]?.removePrefix("Bearer ")?.trim()
                ?: queryParams["token"]

            val isPublicPath = path == "/status" || path == "/pair"

            if (pairingToken.isNotEmpty() && !isPublicPath && (incomingToken == null || incomingToken != pairingToken)) {
                Log.w(TAG, "Unauthorized request to $path: provided token was invalid or missing")
                val responseJson = JSONObject().apply {
                    put("status", "error")
                    put("error", "Unauthorized")
                    put("message", "Invalid or missing X-Buddy-Token")
                }
                sendHttpResponse(writer, 401, "Unauthorized", responseJson.toString())
                client.close()
                return
            }

            if (path == "/status") {
                handleStatus(writer)
            } else if (path == "/set_pin") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleSetPin(writer, queryParams, bodyJson)
            } else if (path == "/pair") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handlePair(writer, queryParams, bodyJson)
            } else if (path == "/upload_update" && method.equals("POST", ignoreCase = true)) {
                handleUploadUpdate(rawInput, writer, contentLength)
            } else if (path == "/set_schedule") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleSetSchedule(writer, queryParams, bodyJson)
            } else if (path == "/get_schedule") {
                handleGetSchedule(writer)
            } else if (path == "/toggle_wifi") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleToggleWifi(writer, queryParams, bodyJson)
            } else if (path == "/set_volume") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                val stream = AudioPlaybackManager.parseStreamParam(bodyJson, queryParams)
                val level = AudioPlaybackManager.parseLevelParam(bodyJson, queryParams)

                AudioPlaybackManager.applyVolumeChangeOnMainLooper(context, stream, level)

                val state = readCurrentVolumeState()
                scope.launch {
                    repository.updateVolumeState(state)
                }

                val responseJson = AudioPlaybackManager.buildSetVolumeResponse(stream, level, state)
                sendHttpResponse(writer, 200, "OK", responseJson.toString())
            } else if (path == "/volume_report") {
                AudioPlaybackManager.refreshMediaInfo(context)
                val state = readCurrentVolumeState()
                val isMusicActive = AudioPlaybackManager.isMusicActive(context)
                val responseJson = JSONObject().apply {
                    put("type", "VOLUME_REPORT")
                    put("mediaVolume", state.mediaVolume)
                    put("ringtoneVolume", state.ringtoneVolume)
                    put("alarmVolume", state.alarmVolume)
                    put("maxMediaVolume", state.maxMediaVolume)
                    put("maxRingtoneVolume", state.maxRingtoneVolume)
                    put("maxAlarmVolume", state.maxAlarmVolume)
                    put("isMuted", state.isMuted)
                    put("isMusicActive", isMusicActive)
                    if (isMusicActive) {
                        put("mediaTitle", AudioPlaybackManager.currentMediaTitle ?: "")
                        put("mediaArtist", AudioPlaybackManager.currentMediaArtist ?: "")
                        put("mediaPackage", AudioPlaybackManager.currentMediaPackage ?: "")
                    }
                    put("timestamp", System.currentTimeMillis())
                }

                sendHttpResponse(writer, 200, "OK", responseJson.toString())
            } else if (path == "/stop_audio") {
                handleStopAudio(writer)
            } else if (path == "/take_camera_photo") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                val facing = (bodyJson?.optString("facing")?.takeIf { it.isNotBlank() }
                    ?: queryParams["facing"]?.takeIf { it.isNotBlank() }
                    ?: "front").lowercase()
                val flash = if (bodyJson != null && bodyJson.has("flash")) {
                    bodyJson.optBoolean("flash", false)
                } else {
                    queryParams["flash"].equals("true", ignoreCase = true) || queryParams["flash"] == "1"
                }
                handleTakeCameraPhoto(writer, facing, flash)
            } else if (path.contains("/comms/walkie-talkie/simulate_receive")) {
                try {
                    val intent = Intent(context, CommsActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        putExtra("action", "SIMULATE_RECEIVE")
                    }
                    context.startActivity(intent)
                    sendHttpResponse(writer, 200, "OK", "{\"status\":\"success\",\"mode\":\"simulated_receive\"}")
                } catch (e: Exception) {
                    Log.e(TAG, "Error starting simulated comms overlay", e)
                    sendHttpResponse(writer, 500, "Internal Server Error", "{\"error\":\"${e.message}\"}")
                }
            } else if (path == "/take_screenshot") {
                handleTakeScreenshot(writer)
            } else if (path == "/close_app") {
                handleCloseApp(writer)
            } else if (path == "/lock_screen") {
                handleLockScreen(writer)
            } else if (path == "/toggle_block_app") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleToggleBlockApp(writer, queryParams, bodyJson, bodyString)
            } else if (path == "/set_app_rules") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleSetAppRules(writer, queryParams, bodyJson, bodyString)
            } else if (path == "/get_app_rules") {
                handleGetAppRules(writer)
            } else if (path == "/installed_apps") {
                handleGetInstalledApps(writer)
            } else if (path == "/app_history") {
                val days = queryParams["days"]?.toIntOrNull()?.coerceIn(1, 30) ?: 5
                handleGetAppHistory(writer, days)
            } else if (path == "/add_bonus_minutes") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleAddBonusMinutes(writer, queryParams, bodyJson)
            } else if (path == "/award_coins") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                val amount = bodyJson?.optInt("amount", -1).let {
                    if (it != null && it != -1) it else queryParams["amount"]?.toIntOrNull() ?: 0
                }
                val description = bodyJson?.optString("description") ?: queryParams["description"] ?: ""
                val emoji = bodyJson?.optString("emoji") ?: queryParams["emoji"] ?: "⏳"

                val intent = Intent(WidgetUpdateService.ACTION_COIN_AWARD).apply {
                    putExtra("amount", amount)
                    putExtra("description", description)
                    putExtra("emoji", emoji)
                }
                context.sendBroadcast(intent)

                scope.launch {
                    val current = repository.timeBankState.first()
                    repository.updateTimeBankState(current.copy(balance = current.balance + amount))
                }

                sendHttpResponse(writer, 200, "OK", "{\"status\":\"success\",\"awarded\":$amount}")
            } else if (path == "/set_screen_time") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                val remaining = bodyJson?.optInt("totalRemainingMinutes", -1).let {
                    if (it != null && it != -1) it else queryParams["remaining"]?.toIntOrNull() ?: -1
                }
                val limit = bodyJson?.optInt("totalLimitMinutes", -1).let {
                    if (it != null && it != -1) it else queryParams["limit"]?.toIntOrNull() ?: 120
                }
                if (remaining >= 0) {
                    scope.launch {
                        val current = repository.familyTimeData.first()
                        repository.updateFamilyTimeData(
                            current.copy(
                                totalRemainingMinutes = remaining,
                                totalLimitMinutes = limit,
                                lastUpdatedMillis = System.currentTimeMillis()
                            )
                        )
                    }
                    sendHttpResponse(writer, 200, "OK", "{\"status\":\"success\"}")
                } else {
                    sendHttpResponse(writer, 400, "Bad Request", "{\"status\":\"error\",\"message\":\"Missing totalRemainingMinutes\"}")
                }
            } else if (path == "/comms/signaling") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                val instance = WebRtcManager.activeInstance
                if (instance != null && bodyJson != null) {
                    val map = mutableMapOf<String, Any>()
                    bodyJson.keys().forEach { k -> map[k] = bodyJson.get(k) }
                    instance.handleSignalingMessage(map)
                    sendHttpResponse(writer, 200, "OK", "{\"status\":\"success\"}")
                } else {
                    try {
                        val intent = Intent(context, CommsActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            putExtra("action", "RECEIVE")
                        }
                        context.startActivity(intent)
                        sendHttpResponse(writer, 200, "OK", "{\"status\":\"launched\"}")
                    } catch (e: Exception) {
                        sendHttpResponse(writer, 500, "Internal Server Error", "{\"error\":\"${e.message}\"}")
                    }
                }
            } else if (path == "/call_logs") {
                handleGetCallLogs(writer, queryParams)
            } else if (path == "/chat_logs") {
                handleGetChatLogs(writer, queryParams)
            } else if (path == "/clear_communication_history") {
                handleClearCommunicationHistory(writer)
            } else {
                sendHttpResponse(writer, 404, "Not Found", "{\"error\":\"Not Found\"}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling client request", e)
        } finally {
            try { client.close() } catch (_: Exception) {}
        }
    }

    private fun handleUploadUpdate(rawInput: InputStream, writer: PrintWriter, contentLength: Int) {
        val apkFile = File(context.cacheDir, "update_p2p.apk")
        var fileOut: FileOutputStream? = null
        try {
            fileOut = FileOutputStream(apkFile)
            val buffer = ByteArray(8192)
            var bytesRemaining = if (contentLength > 0) contentLength.toLong() else Long.MAX_VALUE
            var totalRead = 0L

            while (bytesRemaining > 0) {
                val toRead = if (bytesRemaining < buffer.size) bytesRemaining.toInt() else buffer.size
                val read = rawInput.read(buffer, 0, toRead)
                if (read == -1) break
                fileOut.write(buffer, 0, read)
                totalRead += read
                if (contentLength > 0) {
                    bytesRemaining -= read
                }
            }
            fileOut.flush()
        } catch (e: Exception) {
            Log.e(TAG, "Error saving uploaded APK", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
            return
        } finally {
            try {
                fileOut?.close()
            } catch (ignored: Exception) {}
        }

        // Validate file size (> 1MB)
        if (apkFile.length() <= 1024 * 1024) {
            Log.w(TAG, "Uploaded APK validation failed: size is ${apkFile.length()} bytes, expected > 1MB")
            sendHttpResponse(writer, 400, "Bad Request", "{\"status\":\"error\",\"message\":\"File size must be greater than 1MB\"}")
            return
        }

        try {
            val apkUri = FileProvider.getUriForFile(context, "com.familylink.buddy.child.fileprovider", apkFile)
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(installIntent)

            val responseJson = JSONObject().apply {
                put("status", "success")
                put("message", "APK received, installer launched")
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error launching package installer for uploaded APK", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"Failed to launch installer: ${e.message}\"}")
        }
    }

    private fun handleStopAudio(writer: PrintWriter) {
        AudioPlaybackManager.stopPlayback(context)
        scope.launch {
            val state = readCurrentVolumeState()
            repository.updateVolumeState(state)
        }
        val responseJson = JSONObject().apply {
            put("status", "success")
            put("isMusicActive", false)
        }
        sendHttpResponse(writer, 200, "OK", responseJson.toString())
    }

    private fun handleTakeCameraPhoto(writer: PrintWriter, facing: String, flash: Boolean) {
        val latch = CountDownLatch(1)
        var resultBytes: ByteArray? = null
        var errorMessage: String? = null

        SilentCameraManager.capturePhoto(context, facing, flash) { result ->
            result.fold(
                onSuccess = { bytes ->
                    resultBytes = bytes
                },
                onFailure = { error ->
                    errorMessage = error.message ?: "Camera capture failed"
                }
            )
            latch.countDown()
        }

        val completed = try {
            latch.await(7, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            false
        }

        if (!completed) {
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", "Camera capture request timed out")
            }
            sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
            return
        }

        val bytes = resultBytes
        if (bytes != null) {
            val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("base64Image", base64)
                put("facing", facing)
                put("flash", flash)
                put("timestamp", System.currentTimeMillis())
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } else {
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", errorMessage ?: "Unknown error capturing camera photo")
            }
            sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
        }
    }

    private fun handleTakeScreenshot(writer: PrintWriter) {
        val latch = CountDownLatch(1)
        var resultBase64: String? = null
        var resultForegroundApp = "Unbekannt"
        var resultForegroundPackage = ""
        var errorMessage: String? = null

        WifiAccessibilityHelperService.captureScreenshot { base64, foregroundApp, foregroundPackage, error ->
            resultBase64 = base64
            resultForegroundApp = foregroundApp
            resultForegroundPackage = foregroundPackage
            errorMessage = error
            latch.countDown()
        }

        val completed = try {
            latch.await(10, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            false
        }

        if (!completed) {
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", "Screenshot request timed out")
            }
            sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
            return
        }

        if (resultBase64 != null) {
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("base64Image", resultBase64)
                put("foregroundApp", resultForegroundApp)
                put("foregroundPackage", resultForegroundPackage)
                put("timestamp", System.currentTimeMillis())
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } else {
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", errorMessage ?: "Unknown error capturing screenshot")
            }
            sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
        }
    }

    private fun handleCloseApp(writer: PrintWriter) {
        try {
            WifiAccessibilityHelperService.closeCurrentApp(context)
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("message", "Foreground app closed")
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error closing current app", e)
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", "Failed to close foreground app: ${e.message}")
            }
            sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
        }
    }

    private fun handleLockScreen(writer: PrintWriter) {
        try {
            val success = WifiAccessibilityHelperService.lockScreen(context)
            if (success) {
                val responseJson = JSONObject().apply {
                    put("status", "success")
                    put("message", "Screen locked")
                }
                sendHttpResponse(writer, 200, "OK", responseJson.toString())
            } else {
                val responseJson = JSONObject().apply {
                    put("status", "error")
                    put("message", "Failed to lock screen (accessibility service may not be running)")
                }
                sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error locking screen", e)
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", "Failed to lock screen: ${e.message}")
            }
            sendHttpResponse(writer, 500, "Internal Server Error", responseJson.toString())
        }
    }

    private fun handleSetSchedule(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?
    ) {
        val isEnabled = if (bodyJson?.has("enabled") == true) {
            bodyJson.getBoolean("enabled")
        } else if (bodyJson?.has("isEnabled") == true) {
            bodyJson.getBoolean("isEnabled")
        } else if (queryParams.containsKey("enabled")) {
            queryParams["enabled"]?.equals("true", ignoreCase = true) == true || queryParams["enabled"] == "1"
        } else if (queryParams.containsKey("isEnabled")) {
            queryParams["isEnabled"]?.equals("true", ignoreCase = true) == true || queryParams["isEnabled"] == "1"
        } else {
            true
        }

        val bedtimeHour = if (bodyJson?.has("bedtimeHour") == true) {
            bodyJson.getInt("bedtimeHour")
        } else {
            queryParams["bedtimeHour"]?.toIntOrNull() ?: 20
        }

        val bedtimeMinute = if (bodyJson?.has("bedtimeMinute") == true) {
            bodyJson.getInt("bedtimeMinute")
        } else {
            queryParams["bedtimeMinute"]?.toIntOrNull() ?: 30
        }

        val wakeupHour = if (bodyJson?.has("wakeupHour") == true) {
            bodyJson.getInt("wakeupHour")
        } else {
            queryParams["wakeupHour"]?.toIntOrNull() ?: 6
        }

        val wakeupMinute = if (bodyJson?.has("wakeupMinute") == true) {
            bodyJson.getInt("wakeupMinute")
        } else {
            queryParams["wakeupMinute"]?.toIntOrNull() ?: 45
        }

        val activeDays = if (bodyJson?.has("activeDays") == true) {
            val arr = bodyJson.optJSONArray("activeDays")
            if (arr != null) {
                (0 until arr.length()).map { arr.getInt(it) }
            } else {
                listOf(1, 2, 3, 4, 5, 6, 7)
            }
        } else if (queryParams.containsKey("activeDays")) {
            queryParams["activeDays"]?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: listOf(1, 2, 3, 4, 5, 6, 7)
        } else {
            listOf(1, 2, 3, 4, 5, 6, 7)
        }

        val schedule = BedtimeSchedule(
            isEnabled = isEnabled,
            bedtimeHour = bedtimeHour,
            bedtimeMinute = bedtimeMinute,
            wakeupHour = wakeupHour,
            wakeupMinute = wakeupMinute,
            activeDays = if (activeDays.isNotEmpty()) activeDays else listOf(1, 2, 3, 4, 5, 6, 7)
        )

        scope.launch {
            repository.updateBedtimeSchedule(schedule)
            BedtimeScheduleReceiver.scheduleNextAlarms(context, schedule)
            Log.d(TAG, "Updated bedtime schedule via LocalHttpServer: $schedule")
        }

        sendHttpResponse(writer, 200, "OK", "{\"status\": \"success\"}")
    }

    private fun handleGetSchedule(writer: PrintWriter) {
        val schedule = repository.getBedtimeScheduleSync()
        val scheduleJson = JSONObject().apply {
            put("isEnabled", schedule.isEnabled)
            put("bedtimeHour", schedule.bedtimeHour)
            put("bedtimeMinute", schedule.bedtimeMinute)
            put("wakeupHour", schedule.wakeupHour)
            put("wakeupMinute", schedule.wakeupMinute)
            val daysArray = JSONArray()
            schedule.activeDays.forEach { daysArray.put(it) }
            put("activeDays", daysArray)
            put("isCurrentlyBlocked", schedule.isCurrentlyBlocked)
        }
        val responseJson = JSONObject().apply {
            put("status", "success")
            put("schedule", scheduleJson)
        }
        sendHttpResponse(writer, 200, "OK", responseJson.toString())
    }

    private fun handleToggleWifi(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?
    ) {
        val block = if (bodyJson?.has("block") == true) {
            bodyJson.getBoolean("block")
        } else if (queryParams.containsKey("block")) {
            queryParams["block"]?.equals("true", ignoreCase = true) == true || queryParams["block"] == "1"
        } else {
            false
        }

        val turnOn = if (bodyJson?.has("turnOn") == true) {
            bodyJson.getBoolean("turnOn")
        } else if (queryParams.containsKey("turnOn")) {
            queryParams["turnOn"]?.equals("true", ignoreCase = true) == true || queryParams["turnOn"] == "1"
        } else {
            !block
        }

        Log.i(TAG, "LocalHttpServer requestToggle: turnOn=$turnOn")
        WifiAccessibilityHelperService.requestToggle(context, turnOn)
        sendHttpResponse(writer, 200, "OK", "{\"status\": \"success\"}")
    }

    private fun readLineFromStream(input: InputStream): String? {
        val sb = StringBuilder()
        var b = input.read()
        if (b == -1) return null
        while (b != -1) {
            if (b == '\n'.code) {
                if (sb.isNotEmpty() && sb.last() == '\r') {
                    sb.deleteCharAt(sb.length - 1)
                }
                return sb.toString()
            }
            sb.append(b.toChar())
            b = input.read()
        }
        return sb.toString()
    }

    private fun readBodyString(input: InputStream, contentLength: Int): String {
        if (contentLength <= 0) return ""
        val bytes = ByteArray(contentLength)
        var totalRead = 0
        while (totalRead < contentLength) {
            val read = input.read(bytes, totalRead, contentLength - totalRead)
            if (read == -1) break
            totalRead += read
        }
        return String(bytes, 0, totalRead, Charsets.UTF_8)
    }

    private fun applyVolumeChange(stream: String, level: Int) {
        AudioPlaybackManager.applyVolumeChangeOnMainLooper(context, stream, level)
        scope.launch {
            val state = readCurrentVolumeState()
            repository.updateVolumeState(state)
        }
    }

    private fun setStreamVolume(audioManager: AudioManager, streamType: Int, level: Int) {
        AudioPlaybackManager.setStreamVolume(context, audioManager, streamType, level)
    }

    private fun readCurrentVolumeState(): VolumeState {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val isMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.isStreamMute(AudioManager.STREAM_MUSIC) || audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) == 0
        } else {
            audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) == 0
        }
        return VolumeState(
            mediaVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
            ringtoneVolume = audioManager.getStreamVolume(AudioManager.STREAM_RING),
            alarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
            maxMediaVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            maxRingtoneVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING),
            maxAlarmVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            isMuted = isMuted,
            isMusicActive = AudioPlaybackManager.isMusicActive(context)
        )
    }

    private fun handleToggleBlockApp(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?,
        bodyString: String
    ) {
        try {
            val bodyParams = if (bodyString.contains("=") && !bodyString.trim().startsWith("{")) {
                bodyString.split("&").filter { it.contains("=") }.associate {
                    val kv = it.split("=", limit = 2)
                    try {
                        URLDecoder.decode(kv[0], "UTF-8") to URLDecoder.decode(kv.getOrElse(1) { "" }, "UTF-8")
                    } catch (e: Exception) {
                        kv[0] to kv.getOrElse(1) { "" }
                    }
                }
            } else {
                emptyMap()
            }

            val targetPackage = bodyJson?.optString("package")?.takeIf { it.isNotBlank() }
                ?: bodyJson?.optString("packageName")?.takeIf { it.isNotBlank() }
                ?: bodyParams["package"]?.takeIf { it.isNotBlank() }
                ?: bodyParams["packageName"]?.takeIf { it.isNotBlank() }
                ?: queryParams["package"]?.takeIf { it.isNotBlank() }
                ?: queryParams["packageName"]?.takeIf { it.isNotBlank() }
                ?: ""

            if (targetPackage.isBlank()) {
                val responseJson = JSONObject().apply {
                    put("status", "error")
                    put("message", "Missing 'package' parameter")
                }
                sendHttpResponse(writer, 400, "Bad Request", responseJson.toString())
                return
            }

            val isBlocked = if (bodyJson != null && bodyJson.has("blocked")) {
                bodyJson.getBoolean("blocked")
            } else if (bodyJson != null && bodyJson.has("isBlocked")) {
                bodyJson.getBoolean("isBlocked")
            } else if (bodyParams.containsKey("blocked")) {
                bodyParams["blocked"].equals("true", ignoreCase = true) || bodyParams["blocked"] == "1"
            } else if (bodyParams.containsKey("isBlocked")) {
                bodyParams["isBlocked"].equals("true", ignoreCase = true) || bodyParams["isBlocked"] == "1"
            } else if (queryParams.containsKey("blocked")) {
                queryParams["blocked"].equals("true", ignoreCase = true) || queryParams["blocked"] == "1"
            } else if (queryParams.containsKey("isBlocked")) {
                queryParams["isBlocked"].equals("true", ignoreCase = true) || queryParams["isBlocked"] == "1"
            } else {
                true
            }

            val manager = AppLimitsManager.getInstance(context)
            val prefs = context.getSharedPreferences(AppLimitsManager.PREFS_NAME, Context.MODE_PRIVATE)
            val updatedBlacklist = synchronized(manager) {
                manager.toggleAppBlacklist(targetPackage, isBlocked, prefs)
            }

            // Immediately check and intercept foreground app if currently running
            WifiAccessibilityHelperService.checkAndInterceptForeground(context)

            val array = JSONArray()
            updatedBlacklist.forEach { array.put(it) }

            val responseJson = JSONObject().apply {
                put("status", "success")
                put("package", targetPackage)
                put("isBlocked", isBlocked)
                put("blacklistedPackages", array)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error toggling app blacklist over LAN", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleSetAppRules(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?,
        bodyString: String
    ) {
        try {
            val rules = if (bodyJson != null) {
                AppRules.fromJson(bodyJson.toString())
            } else if (queryParams.containsKey("rules")) {
                AppRules.fromJson(queryParams["rules"] ?: "")
            } else if (bodyString.isNotBlank()) {
                AppRules.fromJson(bodyString)
            } else {
                AppRules()
            }

            val manager = AppLimitsManager.getInstance(context)
            synchronized(manager) {
                WifiAccessibilityHelperService.updateAppRules(context, rules)
            }

            val currentRules = manager.getRules()
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("blacklistedCount", currentRules.blacklistedPackages.size)
                put("categoriesCount", currentRules.categories.size)
                put("bonusCount", currentRules.bonusMinutes.size)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error setting app rules over LAN", e)
            sendHttpResponse(writer, 400, "Bad Request", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleGetAppRules(writer: PrintWriter) {
        try {
            val manager = AppLimitsManager.getInstance(context)
            val rules = manager.getRules()
            val usage = manager.getAllCategoryUsageSeconds()
            val bonus = manager.getAllBonusMinutes()

            val responseJson = JSONObject().apply {
                put("status", "success")
                put("rules", JSONObject(rules.toJson()))
                val usageObj = JSONObject()
                usage.forEach { (k, v) -> usageObj.put(k, v) }
                put("categoryUsageSeconds", usageObj)
                val bonusObj = JSONObject()
                bonus.forEach { (k, v) -> bonusObj.put(k, v) }
                put("bonusMinutes", bonusObj)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app rules over LAN", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleGetInstalledApps(writer: PrintWriter) {
        try {
            val apps = InstalledAppsManager.scanInstalledLauncherApps(context)
            val array = JSONArray()
            apps.forEach { app ->
                val obj = JSONObject()
                obj.put("packageName", app["packageName"])
                obj.put("label", app["label"])
                array.put(obj)
            }
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("installedApps", array)
                put("count", apps.size)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error getting installed apps over LAN", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleAddBonusMinutes(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?
    ) {
        try {
            val categoryId = bodyJson?.optString("categoryId")
                ?: queryParams["categoryId"]
                ?: ""
            val minutes = bodyJson?.optInt("minutes", -1).let {
                if (it != null && it != -1) it else queryParams["minutes"]?.toIntOrNull() ?: 0
            }

            if (categoryId.isBlank() || minutes <= 0) {
                sendHttpResponse(writer, 400, "Bad Request", "{\"status\":\"error\",\"message\":\"Missing categoryId or valid minutes\"}")
                return
            }

            WifiAccessibilityHelperService.addBonusMinutes(context, categoryId, minutes)

            val responseJson = JSONObject().apply {
                put("status", "success")
                put("categoryId", categoryId)
                put("addedMinutes", minutes)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error adding bonus minutes over LAN", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleGetAppHistory(writer: PrintWriter, days: Int) {
        try {
            val now = System.currentTimeMillis()
            val startTime = now - (days * 24 * 60 * 60 * 1000L)
            val historyArray = JSONArray()

            val dbRecords = CommunicationDatabaseHelper.getInstance(context).getAppHistorySince(startTime, limit = 500)
            if (dbRecords.isNotEmpty()) {
                for (record in dbRecords) {
                    val item = JSONObject().apply {
                        put("packageName", record.packageName)
                        put("label", record.appLabel)
                        put("timestamp", record.timestamp)
                    }
                    historyArray.put(item)
                }
            } else {
                val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                if (usageStatsManager != null) {
                    val events = usageStatsManager.queryEvents(startTime, now)
                    val event = UsageEvents.Event()
                    val pm = context.packageManager
                    val labelCache = HashMap<String, String>()

                    while (events != null && events.hasNextEvent()) {
                        events.getNextEvent(event)
                        if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                            val pkg = event.packageName ?: continue

                            // Filter out system UI, launchers, and allowed apps (Spotify, child app, settings, dialer)
                            if (pkg == "com.android.systemui" ||
                                WifiAccessibilityHelperService.isLauncherPackage(context, pkg) ||
                                InstalledAppsManager.isAllowedExcludedApp(context, pkg)) {
                                continue
                            }

                            val label = labelCache.getOrPut(pkg) {
                                try {
                                    val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                        pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
                                    } else {
                                        @Suppress("DEPRECATION")
                                        pm.getApplicationInfo(pkg, 0)
                                    }
                                    val l = pm.getApplicationLabel(appInfo).toString()
                                    if (l.isNotBlank()) l else pkg
                                } catch (e: Exception) {
                                    pkg
                                }
                            }

                            val item = JSONObject().apply {
                                put("packageName", pkg)
                                put("label", label)
                                put("timestamp", event.timeStamp)
                            }
                            historyArray.put(item)
                        }
                    }
                }
            }

            val responseJson = JSONObject().apply {
                put("status", "success")
                put("history", historyArray)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error querying app history over LAN", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleStatus(writer: PrintWriter) {
        AudioPlaybackManager.refreshMediaInfo(context)
        val deviceId = repository.getDeviceIdSync()
        val deviceName = getDeviceName()
        val isMusicActive = AudioPlaybackManager.isMusicActive(context)
        val schedule = repository.getBedtimeScheduleSync()
        val responseJson = JSONObject().apply {
            put("status", "online")
            put("deviceId", deviceId)
            put("deviceName", deviceName)
            put("version", BuildConfig.VERSION_NAME)
            put("hasParentPin", repository.isPinConfiguredSync())
            put("isMusicActive", isMusicActive)
            if (isMusicActive) {
                put("mediaTitle", AudioPlaybackManager.currentMediaTitle ?: "")
                put("mediaArtist", AudioPlaybackManager.currentMediaArtist ?: "")
                put("mediaPackage", AudioPlaybackManager.currentMediaPackage ?: "")
            }
            put("bedtimeEnabled", schedule.isEnabled)
            put("isBedtimeBlocked", schedule.isCurrentlyBlocked)
        }
        sendHttpResponse(writer, 200, "OK", responseJson.toString())
    }

    private fun handleSetPin(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?
    ) {
        val pin = bodyJson?.optString("pin")
            ?: queryParams["pin"]
            ?: ""
        if (pin.isBlank()) {
            scope.launch {
                repository.setParentPin(null)
            }
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("message", "PIN removed")
                put("hasParentPin", false)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } else if (com.familylink.buddy.child.data.ParentPinManager.isValidPinFormat(pin)) {
            scope.launch {
                repository.setParentPin(pin)
            }
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("message", "PIN set")
                put("hasParentPin", true)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } else {
            val responseJson = JSONObject().apply {
                put("status", "error")
                put("message", "Invalid PIN format: must be 4 digits")
            }
            sendHttpResponse(writer, 400, "Bad Request", responseJson.toString())
        }
    }

    private fun handlePair(
        writer: PrintWriter,
        queryParams: Map<String, String>,
        bodyJson: JSONObject?
    ) {
        val deviceId = repository.getDeviceIdSync()
        val deviceName = getDeviceName()
        val requestedToken = bodyJson?.optString("token")
            ?: queryParams["token"]
            ?: ""

        val tokenToUse = if (requestedToken.isNotBlank()) {
            scope.launch {
                repository.updateDeviceToken(requestedToken)
            }
            requestedToken
        } else {
            repository.getOrCreateDeviceTokenSync()
        }

        val responseJson = JSONObject().apply {
            put("status", "paired")
            put("deviceId", deviceId)
            put("deviceName", deviceName)
            put("token", tokenToUse)
        }
        sendHttpResponse(writer, 200, "OK", responseJson.toString())
    }

    private fun handleGetCallLogs(writer: PrintWriter, queryParams: Map<String, String>) {
        try {
            val since = queryParams["since"]?.toLongOrNull() ?: 0L
            val limit = queryParams["limit"]?.toIntOrNull()?.coerceIn(1, 500) ?: 100

            if (CallLogManager.hasCallLogPermission(context)) {
                CallLogManager.syncCallLogs(context, since, limit)
            }

            val calls = CommunicationDatabaseHelper.getInstance(context).getCallsSince(since, limit)
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("calls", calls.toJsonArray())
                put("count", calls.size)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error handling getCallLogs: ${e.message}", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleGetChatLogs(writer: PrintWriter, queryParams: Map<String, String>) {
        try {
            val since = queryParams["since"]?.toLongOrNull() ?: 0L
            val pkg = queryParams["package"]?.takeIf { it.isNotBlank() }
            val limit = queryParams["limit"]?.toIntOrNull()?.coerceIn(1, 500) ?: 200

            val chats = CommunicationDatabaseHelper.getInstance(context).getChatsSince(since, pkg, limit)
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("chats", chats.toJsonArray())
                put("count", chats.size)
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error handling getChatLogs: ${e.message}", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun handleClearCommunicationHistory(writer: PrintWriter) {
        try {
            CommunicationDatabaseHelper.getInstance(context).clearAll()
            val responseJson = JSONObject().apply {
                put("status", "success")
                put("message", "Communication history cleared")
            }
            sendHttpResponse(writer, 200, "OK", responseJson.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing communication history: ${e.message}", e)
            sendHttpResponse(writer, 500, "Internal Server Error", "{\"status\":\"error\",\"message\":\"${e.message}\"}")
        }
    }

    private fun getDeviceName(): String {
        return try {
            Settings.Global.getString(context.contentResolver, "device_name")
                ?: Settings.Secure.getString(context.contentResolver, "bluetooth_name")
                ?: Build.MODEL
        } catch (e: Exception) {
            Build.MODEL
        } ?: "Child Tablet"
    }

    private fun sendHttpResponse(writer: PrintWriter, statusCode: Int, statusText: String, body: String) {
        writer.println("HTTP/1.1 $statusCode $statusText")
        writer.println("Content-Type: application/json")
        writer.println("Content-Length: ${body.toByteArray(Charsets.UTF_8).size}")
        writer.println("Access-Control-Allow-Origin: *")
        writer.println("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE")
        writer.println("Access-Control-Allow-Headers: X-Buddy-Token, Authorization, Content-Type, Accept, Origin")
        writer.println("Access-Control-Max-Age: 86400")
        writer.println()
        writer.print(body)
        writer.flush()
    }
}
