package com.familylink.buddy.child.service

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import com.familylink.buddy.child.data.BedtimeSchedule
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.data.VolumeState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
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
        private const val PORT = 8085
    }

    private var serverSocket: ServerSocket? = null
    private var isRunning = false
    private val scope = CoroutineScope(Dispatchers.IO)

    fun start() {
        if (isRunning) return
        isRunning = true
        Thread {
            try {
                serverSocket = ServerSocket(PORT)
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
            }
        }.start()
    }

    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
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

            if (path == "/upload_update" && method.equals("POST", ignoreCase = true)) {
                handleUploadUpdate(rawInput, writer, contentLength)
            } else if (path == "/set_schedule") {
                val bodyString = readBodyString(rawInput, contentLength)
                val bodyJson = try {
                    if (bodyString.isNotBlank()) JSONObject(bodyString) else null
                } catch (e: Exception) {
                    null
                }
                handleSetSchedule(writer, queryParams, bodyJson)
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
                val stream = bodyJson?.optString("stream") ?: queryParams["stream"] ?: "MEDIA"
                val level = bodyJson?.optInt("level", -1).let {
                    if (it != null && it != -1) it else queryParams["level"]?.toIntOrNull() ?: 0
                }

                applyVolumeChange(stream, level)

                val responseJson = JSONObject().apply {
                    put("status", "success")
                    put("stream", stream)
                    put("level", level)
                }

                sendHttpResponse(writer, 200, "OK", responseJson.toString())
            } else if (path == "/volume_report") {
                val state = readCurrentVolumeState()
                val responseJson = JSONObject().apply {
                    put("type", "VOLUME_REPORT")
                    put("mediaVolume", state.mediaVolume)
                    put("ringtoneVolume", state.ringtoneVolume)
                    put("alarmVolume", state.alarmVolume)
                    put("maxMediaVolume", state.maxMediaVolume)
                    put("maxRingtoneVolume", state.maxRingtoneVolume)
                    put("maxAlarmVolume", state.maxAlarmVolume)
                    put("isMuted", state.isMuted)
                    put("timestamp", System.currentTimeMillis())
                }

                sendHttpResponse(writer, 200, "OK", responseJson.toString())
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
            } else {
                sendHttpResponse(writer, 404, "Not Found", "{\"error\":\"Not Found\"}")
            }

            client.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error handling client request", e)
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
            latch.await(5, TimeUnit.SECONDS)
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
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val streamType = when (stream) {
            "MEDIA" -> AudioManager.STREAM_MUSIC
            "RINGTONE" -> AudioManager.STREAM_RING
            "ALARM" -> AudioManager.STREAM_ALARM
            else -> AudioManager.STREAM_MUSIC
        }

        if (stream == "ALL") {
            setStreamVolume(audioManager, AudioManager.STREAM_MUSIC, level)
            setStreamVolume(audioManager, AudioManager.STREAM_RING, level)
            setStreamVolume(audioManager, AudioManager.STREAM_ALARM, level)
        } else {
            setStreamVolume(audioManager, streamType, level)
        }

        // Persist the state change locally
        scope.launch {
            val state = readCurrentVolumeState()
            repository.updateVolumeState(state)
        }
    }

    private fun setStreamVolume(audioManager: AudioManager, streamType: Int, level: Int) {
        try {
            if (streamType == AudioManager.STREAM_RING && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (notificationManager?.isNotificationPolicyAccessGranted != true) {
                    Log.w(TAG, "Skipping STREAM_RING: DND access not granted")
                    return
                }
            }
            val max = audioManager.getStreamMaxVolume(streamType)
            val clamped = level.coerceIn(0, max)
            audioManager.setStreamVolume(streamType, clamped, 0)
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException setting stream $streamType volume (likely DND): ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting stream volume for $streamType", e)
        }
    }

    private fun readCurrentVolumeState(): VolumeState {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return VolumeState(
            mediaVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
            ringtoneVolume = audioManager.getStreamVolume(AudioManager.STREAM_RING),
            alarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
            maxMediaVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            maxRingtoneVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING),
            maxAlarmVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            isMuted = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) == 0
        )
    }

    private fun sendHttpResponse(writer: PrintWriter, statusCode: Int, statusText: String, body: String) {
        writer.println("HTTP/1.1 $statusCode $statusText")
        writer.println("Content-Type: application/json")
        writer.println("Content-Length: ${body.toByteArray(Charsets.UTF_8).size}")
        writer.println("Access-Control-Allow-Origin: *")
        writer.println()
        writer.print(body)
        writer.flush()
    }
}
