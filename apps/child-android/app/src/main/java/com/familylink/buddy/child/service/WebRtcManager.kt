package com.familylink.buddy.child.service

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.webrtc.*
import org.webrtc.audio.JavaAudioDeviceModule
import java.nio.ByteBuffer

class WebRtcManager(
    private val context: Context,
    private val coroutineScope: CoroutineScope
) {
    companion object {
        private const val TAG = "WebRtcManager"
        @Volatile
        var activeInstance: WebRtcManager? = null
    }

    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var localAudioTrack: org.webrtc.AudioTrack? = null
    private var activeSessionId: String? = null
    private var deviceToken: String? = null

    // Callbacks
    var onOutgoingSignalingMessage: ((type: String, payload: Map<String, Any>) -> Unit)? = null

    // Emulator simulate variables
    private var isSimulating = false
    private var simulationJob: Job? = null
    private var audioTrackMock: AudioTrack? = null

    // Callbacks
    var onStreamStateChanged: ((isPlaying: Boolean) -> Unit)? = null
    var onSessionClosed: (() -> Unit)? = null

    init {
        activeInstance = this
        checkEmulatorMode()
        initWebRtc()
    }

    private fun checkEmulatorMode() {
        val brand = Build.BRAND ?: ""
        val device = Build.DEVICE ?: ""
        val hardware = Build.HARDWARE ?: ""
        val model = Build.MODEL ?: ""
        val product = Build.PRODUCT ?: ""
        
        val runningOnEmulator = (brand.startsWith("generic") && device.startsWith("generic"))
                || hardware.contains("goldfish")
                || hardware.contains("ranchu")
                || model.contains("google_sdk")
                || model.contains("Emulator")
                || model.contains("Android SDK built for x86")
                || product.contains("sdk_google")
                || product.contains("google_sdk")
                || product.contains("emulator")
                || product.contains("simulator")

        if (runningOnEmulator) {
            Log.i(TAG, "Running on Android Emulator: forcing Walkie-Talkie Simulation Mode")
            isSimulating = true
        }
    }

    private fun initWebRtc() {
        try {
            // Initialize WebRTC PeerConnectionFactory
            val options = PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(true)
                .createInitializationOptions()
            PeerConnectionFactory.initialize(options)

            val factoryOptions = PeerConnectionFactory.Options()
            val audioDeviceModule = JavaAudioDeviceModule.builder(context).createAudioDeviceModule()

            peerConnectionFactory = PeerConnectionFactory.builder()
                .setOptions(factoryOptions)
                .setAudioDeviceModule(audioDeviceModule)
                .createPeerConnectionFactory()
            
            Log.d(TAG, "WebRTC Factory initialized successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "WebRTC JNI libraries not found, running in EMULATOR Fallback Mode", e)
            isSimulating = true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize WebRTC standard client, fallback enabled", e)
            isSimulating = true
        }
    }

    /**
     * Set up local signaling session
     */
    fun startListeningToSignaling(deviceToken: String, sessionId: String) {
        if (deviceToken.isEmpty() || sessionId.isEmpty()) return
        this.deviceToken = deviceToken
        closeActiveSession()
        activeSessionId = sessionId
        activeInstance = this
        Log.d(TAG, "WebRtcManager ready for local signaling session: $sessionId")
    }

    fun handleSignalingMessage(data: Map<String, Any>) {
        val type = data["type"] as? String ?: return
        Log.d(TAG, "Incoming signaling payload: type=$type")

        if (isSimulating) {
            handleSimulatedSignaling(type, data)
            return
        }

        when (type) {
            "OFFER" -> {
                val sdp = data["sdp"] as? String ?: return
                handleWebRtcOffer(sdp)
            }
            "ANSWER" -> {
                val sdp = data["sdp"] as? String ?: return
                handleWebRtcAnswer(sdp)
            }
            "ICE_CANDIDATE" -> {
                val sdpMid = data["sdpMid"] as? String ?: ""
                val sdpMLineIndex = (data["sdpMLineIndex"] as? Number)?.toInt() ?: 0
                val candidateSdp = data["candidate"] as? String ?: ""
                addIceCandidate(sdpMid, sdpMLineIndex, candidateSdp)
            }
            "CLOSE" -> {
                closeActiveSession()
            }
        }
    }

    private fun handleWebRtcOffer(sdp: String) {
        createPeerConnection()
        peerConnection?.setRemoteDescription(object : SimpleSdpObserver() {
            override fun onSetSuccess() {
                peerConnection?.createAnswer(object : SimpleSdpObserver() {
                    override fun onCreateSuccess(desc: SessionDescription?) {
                        desc?.let { answer ->
                            peerConnection?.setLocalDescription(object : SimpleSdpObserver() {
                                override fun onSetSuccess() {
                                    sendSdpResponse("ANSWER", answer.description)
                                }
                            }, answer)
                        }
                    }
                }, MediaConstraints())
            }
        }, SessionDescription(SessionDescription.Type.OFFER, sdp))
    }

    private fun handleWebRtcAnswer(sdp: String) {
        peerConnection?.setRemoteDescription(object : SimpleSdpObserver(), SdpObserver {
            override fun onSetSuccess() {
                Log.d(TAG, "Remote answer set successfully")
            }
        }, SessionDescription(SessionDescription.Type.ANSWER, sdp))
    }

    private fun addIceCandidate(sdpMid: String, sdpMLineIndex: Int, candidateSdp: String) {
        val candidate = IceCandidate(sdpMid, sdpMLineIndex, candidateSdp)
        peerConnection?.addIceCandidate(candidate)
    }

    private fun createPeerConnection() {
        if (peerConnection != null) return

        val rtcConfig = PeerConnection.RTCConfiguration(listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
        ))
        
        peerConnection = peerConnectionFactory?.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
                Log.d(TAG, "ICE Connection State: $state")
                if (state == PeerConnection.IceConnectionState.CONNECTED) {
                    onStreamStateChanged?.invoke(true)
                } else if (state == PeerConnection.IceConnectionState.DISCONNECTED || 
                           state == PeerConnection.IceConnectionState.FAILED) {
                    onStreamStateChanged?.invoke(false)
                }
            }
            override fun onIceConnectionReceivingChange(p0: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {}
            override fun onIceCandidate(candidate: IceCandidate?) {
                candidate?.let {
                    sendIceCandidate(it)
                }
            }
            override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}
            override fun onAddStream(p0: MediaStream?) {
                p0?.audioTracks?.firstOrNull()?.let {
                    Log.d(TAG, "Received remote audio track")
                    onStreamStateChanged?.invoke(true)
                }
            }
            override fun onRemoveStream(p0: MediaStream?) {
                onStreamStateChanged?.invoke(false)
            }
            override fun onDataChannel(p0: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver?, mediaStreams: Array<out MediaStream>?) {}
        })

        // Add local audio
        val audioSource = peerConnectionFactory?.createAudioSource(MediaConstraints())
        val track = peerConnectionFactory?.createAudioTrack("local_audio_track", audioSource)
        localAudioTrack = track
        if (track != null) {
            peerConnection?.addTrack(track, listOf("local_media_stream"))
        }
    }

    private fun sendSdpResponse(type: String, sdp: String) {
        val sessionId = activeSessionId ?: return
        val updates = mapOf(
            "type" to type,
            "sdp" to sdp,
            "sessionId" to sessionId,
            "timestamp" to System.currentTimeMillis()
        )
        onOutgoingSignalingMessage?.invoke(type, updates)
        Log.d(TAG, "Outgoing SDP response generated: type=$type")
    }

    private fun sendIceCandidate(candidate: IceCandidate) {
        val sessionId = activeSessionId ?: return
        val updates = mapOf(
            "type" to "ICE_CANDIDATE",
            "sdpMid" to candidate.sdpMid,
            "sdpMLineIndex" to candidate.sdpMLineIndex,
            "candidate" to candidate.sdp,
            "sessionId" to sessionId,
            "timestamp" to System.currentTimeMillis()
        )
        onOutgoingSignalingMessage?.invoke("ICE_CANDIDATE", updates)
        Log.d(TAG, "Outgoing ICE candidate generated")
    }

    // --- Emulator Simulation Engine ---
    private fun handleSimulatedSignaling(type: String, data: Map<String, Any>) {
        when (type) {
            "OFFER" -> {
                Log.d(TAG, "Simulated Offer: establishing local media mockup stream")
                onStreamStateChanged?.invoke(true)
                playSimulatedAudioStream()
            }
            "CLOSE" -> {
                closeActiveSession()
            }
        }
    }

    private fun playSimulatedAudioStream() {
        simulationJob?.cancel()
        simulationJob = coroutineScope.launch(Dispatchers.Default) {
            val sampleRate = 8000
            val bufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            
            val audioTrack = AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
            audioTrackMock = audioTrack
            audioTrack.play()

            // Play a synthetic repeating tone representing walkie-talkie audio stream
            val frequency = 440.0
            val buffer = ShortArray(bufferSize)
            var angle = 0.0
            
            while (isActive) {
                for (i in buffer.indices) {
                    buffer[i] = (Math.sin(angle) * 32767).toInt().toShort()
                    angle += 2.0 * Math.PI * frequency / sampleRate
                }
                audioTrack.write(buffer, 0, buffer.size)
                delay(50)
            }
        }
    }

    fun triggerLocalSpeakSimulation() {
        if (!isSimulating) return
        onStreamStateChanged?.invoke(true)
        playSimulatedAudioStream()
    }

    fun stopLocalSpeakSimulation() {
        if (!isSimulating) return
        simulationJob?.cancel()
        audioTrackMock?.stop()
        audioTrackMock?.release()
        audioTrackMock = null
        onStreamStateChanged?.invoke(false)
    }

    fun closeActiveSession() {
        if (activeInstance == this) {
            activeInstance = null
        }

        peerConnection?.close()
        peerConnection = null
        localAudioTrack = null

        simulationJob?.cancel()
        simulationJob = null
        audioTrackMock?.stop()
        audioTrackMock?.release()
        audioTrackMock = null

        activeSessionId = null
        onSessionClosed?.invoke()
        onStreamStateChanged?.invoke(false)
        Log.d(TAG, "Active WebRTC session closed and cleaned up")
    }

    private open class SimpleSdpObserver : SdpObserver {
        override fun onCreateSuccess(desc: SessionDescription?) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(reason: String?) {
            Log.e(TAG, "SDP observer creation error: $reason")
        }
        override fun onSetFailure(reason: String?) {
            Log.e(TAG, "SDP observer set error: $reason")
        }
    }
}
