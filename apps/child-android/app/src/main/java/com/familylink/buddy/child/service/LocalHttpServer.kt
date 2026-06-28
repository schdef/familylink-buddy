package com.familylink.buddy.child.service

import android.content.Context
import android.media.AudioManager
import android.util.Log
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.data.VolumeState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.SocketException

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

    private fun handleClient(client: java.net.Socket) {
        try {
            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
            val writer = PrintWriter(client.getOutputStream())

            val firstLine = reader.readLine() ?: ""
            Log.d(TAG, "Received request: $firstLine")

            if (firstLine.startsWith("POST /set_volume") || firstLine.startsWith("GET /set_volume")) {
                // Parse query parameters
                // E.g. GET /set_volume?stream=MEDIA&level=8
                val pathAndQuery = firstLine.split(" ").getOrNull(1) ?: ""
                val query = pathAndQuery.split("?").getOrNull(1) ?: ""
                val params = query.split("&").associate {
                    val parts = it.split("=")
                    parts.getOrNull(0) to (parts.getOrNull(1) ?: "")
                }

                val stream = params["stream"] ?: "MEDIA"
                val level = params["level"]?.toIntOrNull() ?: 0

                applyVolumeChange(stream, level)

                val responseJson = JSONObject().apply {
                    put("status", "success")
                    put("stream", stream)
                    put("level", level)
                }

                sendHttpResponse(writer, 200, "OK", responseJson.toString())
            } else if (firstLine.startsWith("GET /volume_report")) {
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
            } else {
                sendHttpResponse(writer, 404, "Not Found", "{\"error\":\"Not Found\"}")
            }

            client.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error handling client request", e)
        }
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
        val max = audioManager.getStreamMaxVolume(streamType)
        val clamped = level.coerceIn(0, max)
        audioManager.setStreamVolume(streamType, clamped, 0)
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
        writer.println("Content-Length: ${body.length}")
        writer.println("Access-Control-Allow-Origin: *")
        writer.println()
        writer.print(body)
        writer.flush()
    }
}
