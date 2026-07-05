package com.familylink.buddy.child.service

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.familylink.buddy.child.R
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

class CommsActivity : ComponentActivity() {

    companion object {
        private const val TAG = "CommsActivity"
    }

    private lateinit var webRtcManager: WebRtcManager
    private val activityScope = CoroutineScope(Dispatchers.Main)
    private var isIncomingSimulation = false
    private val deviceTokenState = mutableStateOf("")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Show over lockscreen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // Initialize WebRTC wrapper
        webRtcManager = WebRtcManager(applicationContext, activityScope)
        
        val action = intent.getStringExtra("action") ?: ""
        if (action == "SIMULATE_RECEIVE") {
            isIncomingSimulation = true
        }

        setContent {
            CommsScreenContent(
                isSimulation = isIncomingSimulation,
                onClose = {
                    webRtcManager.closeActiveSession()
                    finish()
                },
                webRtcManager = webRtcManager,
                deviceToken = deviceTokenState.value
            )
        }

        // Register signaling listeners
        activityScope.launch {
            val repo = FamilyTimeRepository(applicationContext)
            val volumeState = repo.volumeState.first()
            val token = volumeState.deviceToken
            deviceTokenState.value = token
            
            if (isIncomingSimulation) {
                // Simulate signaling offer internally
                triggerBeepSound()
                triggerVibration()
                delay(200)
                webRtcManager.triggerLocalSpeakSimulation()
            } else if (token.isNotEmpty()) {
                // Listen to actual signaling channel in Firestore
                webRtcManager.startListeningToSignaling(token, "active_session")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        webRtcManager.closeActiveSession()
    }

    private fun triggerBeepSound() {
        try {
            val sampleRate = 8000
            val duration = 0.15
            val numSamples = (duration * sampleRate).toInt()
            val sample = DoubleArray(numSamples)
            val generatedSnd = ByteArray(2 * numSamples)

            for (i in 0 until numSamples) {
                // Double high-pitch roger beep tone
                val freq = if (i < numSamples / 2) 1200.0 else 1600.0
                sample[i] = Math.sin(2 * Math.PI * i / (sampleRate / freq))
            }

            var idx = 0
            for (i in 0 until numSamples) {
                val valSample = (sample[i] * 32767).toInt()
                generatedSnd[idx++] = (valSample and 0x00ff).toByte()
                generatedSnd[idx++] = (valSample and 0xff00 ushr 8).toByte()
            }

            val audioTrack = AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                generatedSnd.size,
                AudioTrack.MODE_STATIC
            )
            audioTrack.write(generatedSnd, 0, generatedSnd.size)
            audioTrack.play()
        } catch (e: Exception) {
            Log.e(TAG, "Error playing synth roger beep", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun triggerVibration() {
        try {
            val pattern = longArrayOf(0, 100, 50, 100, 50, 300)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                vibrator.vibrate(pattern, -1)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering tactile vibration", e)
        }
    }
}

@Composable
fun CommsScreenContent(
    isSimulation: Boolean,
    onClose: () -> Unit,
    webRtcManager: WebRtcManager,
    deviceToken: String
) {
    var sessionState by remember { mutableStateOf("connecting") } // connecting, listening, recording, idle
    var screenFlashAlpha by remember { mutableStateOf(0.4f) }

    // Waveform visualization states
    val infiniteTransition = rememberInfiniteTransition(label = "waveform")
    val waveScale by infiniteTransition.animateFloat(
        initialValue = 0.9f,
        targetValue = 1.3f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "waveformScale"
    )

    // Character rotation animation
    val characterAngle by infiniteTransition.animateFloat(
        initialValue = -5f,
        targetValue = 5f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = EaseInOutSine),
            repeatMode = RepeatMode.Reverse
        ),
        label = "charAngle"
    )

    // Flash/pulse cleanup on load
    LaunchedEffect(Unit) {
        delay(600)
        screenFlashAlpha = 0f // Fade out the initial silent screen flash indicator
    }

    // Bind WebRTC state changes to update the screen state UI
    LaunchedEffect(webRtcManager) {
        webRtcManager.onStreamStateChanged = { isPlaying ->
            sessionState = if (isPlaying) "listening" else "idle"
        }
        webRtcManager.onSessionClosed = {
            sessionState = "idle"
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.5f))
            .pointerInput(Unit) {
                detectTapGestures(onTap = { /* Prevent dismiss on outside tap to avoid accidental closures */ })
            },
        contentAlignment = Alignment.Center
    ) {
        // Silent flash overlay pulsing
        if (screenFlashAlpha > 0f) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White.copy(alpha = screenFlashAlpha))
            )
        }

        // Central Walkie-Talkie Card
        Card(
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = Color(0xFF0F1016)),
            modifier = Modifier
                .width(320.dp)
                .border(2.dp, Color(0xFF6366F1).copy(alpha = 0.5f), RoundedCornerShape(24.dp))
                .padding(16.dp)
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth()
            ) {
                // Header Title
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(
                                when (sessionState) {
                                    "listening" -> Color(0xFFEF4444)
                                    "recording" -> Color(0xFF10B981)
                                    else -> Color(0xFFF59E0B)
                                }
                            )
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = stringResource(id = R.string.comms_overlay_title),
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Pulsing wave visualization background
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(130.dp)
                        .scale(if (sessionState == "listening" || sessionState == "recording") waveScale else 1.0f)
                ) {
                    // Draw customized visual audio waveform circles
                    Canvas(modifier = Modifier.size(120.dp)) {
                        drawCircle(
                            brush = Brush.radialGradient(
                                colors = listOf(
                                    Color(0xFF6366F1).copy(alpha = 0.3f),
                                    Color.Transparent
                                )
                            ),
                            radius = size.minDimension / 2
                        )
                        if (sessionState == "listening" || sessionState == "recording") {
                            drawCircle(
                                color = if (sessionState == "listening") Color(0xFF818CF8) else Color(0xFF34D399),
                                radius = size.minDimension / 2.2f,
                                style = Stroke(width = 2.dp.toPx())
                            )
                        }
                    }

                    // Astronaut Animated Character Reacting
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(76.dp)
                            .rotate(characterAngle)
                    ) {
                        Canvas(modifier = Modifier.fillMaxSize()) {
                            // Helmet / Outer head
                            drawCircle(
                                color = Color(0xFFF1F5F9),
                                radius = 30.dp.toPx()
                            )
                            // Screen / Visor
                            drawCircle(
                                color = Color(0xFF1E293B),
                                radius = 22.dp.toPx()
                            )
                            // Eyes
                            drawCircle(
                                color = if (sessionState == "listening") Color(0xFFEF4444) else Color(0xFF60A5FA),
                                radius = 3.dp.toPx(),
                                center = this.center.copy(x = this.center.x - 8.dp.toPx())
                            )
                            drawCircle(
                                color = if (sessionState == "listening") Color(0xFFEF4444) else Color(0xFF60A5FA),
                                radius = 3.dp.toPx(),
                                center = this.center.copy(x = this.center.x + 8.dp.toPx())
                            )
                            // Antenna
                            drawLine(
                                color = Color(0xFFF1F5F9),
                                start = this.center.copy(y = this.center.y - 30.dp.toPx()),
                                end = this.center.copy(y = this.center.y - 42.dp.toPx()),
                                strokeWidth = 3.dp.toPx()
                            )
                            drawCircle(
                                color = Color(0xFFEF4444),
                                radius = 5.dp.toPx(),
                                center = this.center.copy(y = this.center.y - 42.dp.toPx())
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Active Connection Status Label
                Text(
                    text = when (sessionState) {
                        "connecting" -> stringResource(id = R.string.comms_overlay_connecting)
                        "listening" -> stringResource(id = R.string.comms_overlay_listening)
                        "recording" -> stringResource(id = R.string.comms_overlay_recording)
                        else -> stringResource(id = R.string.comms_overlay_idle)
                    },
                    color = Color(0xFF94A3B8),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                )

                Spacer(modifier = Modifier.height(20.dp))

                // Interaction Action Buttons Row
                Row(
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    // Push-to-Talk button for child reply
                    Button(
                        onClick = {},
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (sessionState == "recording") Color(0xFF10B981) else Color(0xFF1E293B)
                        ),
                        modifier = Modifier
                            .pointerInput(Unit) {
                                detectTapGestures(
                                    onPress = {
                                        sessionState = "recording"
                                        if (isSimulation) {
                                            webRtcManager.triggerLocalSpeakSimulation()
                                        }
                                        if (deviceToken.isNotEmpty()) {
                                            FirebaseFirestore.getInstance().collection("pairings")
                                                .document(deviceToken).update("childIsSpeaking", true)
                                        }
                                        
                                        tryAwaitRelease()
                                        
                                        sessionState = "idle"
                                        if (isSimulation) {
                                            webRtcManager.stopLocalSpeakSimulation()
                                        }
                                        if (deviceToken.isNotEmpty()) {
                                            FirebaseFirestore.getInstance().collection("pairings")
                                                .document(deviceToken).update("childIsSpeaking", false)
                                        }
                                    }
                                )
                            }
                    ) {
                        Text(
                            text = stringResource(id = R.string.comms_overlay_hold_talk),
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    // Acknowledge Quick dismiss button
                    Button(
                        onClick = onClose,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6366F1)),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text(
                            text = stringResource(id = R.string.comms_overlay_ok_btn),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}
