package com.familylink.buddy.child

import android.hardware.camera2.CameraCharacteristics
import android.util.Size
import com.familylink.buddy.child.data.AudioPlaybackManager
import com.familylink.buddy.child.data.SilentCameraManager
import com.familylink.buddy.child.data.VolumeState
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioAndCameraLogicTest {

    @Test
    fun testAudioStopResponseSerialization() {
        val responseJson = AudioPlaybackManager.buildStopAudioResponse(isMusicActive = false)
        assertEquals("success", responseJson.getString("status"))
        assertFalse(responseJson.getBoolean("isMusicActive"))

        val activeResponseJson = AudioPlaybackManager.buildStopAudioResponse(isMusicActive = true)
        assertEquals("success", activeResponseJson.getString("status"))
        assertTrue(activeResponseJson.getBoolean("isMusicActive"))
    }

    @Test
    fun testVolumeStateWithMusicActive() {
        val defaultState = VolumeState()
        assertFalse(defaultState.isMusicActive)

        val activeState = VolumeState(
            mediaVolume = 10,
            ringtoneVolume = 8,
            alarmVolume = 5,
            isMuted = false,
            isMusicActive = true
        )
        assertTrue(activeState.isMusicActive)
        assertEquals(10, activeState.mediaVolume)

        // Test volume report payload structure
        val reportPayload = JSONObject().apply {
            put("type", "VOLUME_REPORT")
            put("mediaVolume", activeState.mediaVolume)
            put("ringtoneVolume", activeState.ringtoneVolume)
            put("alarmVolume", activeState.alarmVolume)
            put("maxMediaVolume", activeState.maxMediaVolume)
            put("maxRingtoneVolume", activeState.maxRingtoneVolume)
            put("maxAlarmVolume", activeState.maxAlarmVolume)
            put("isMuted", activeState.isMuted)
            put("isMusicActive", activeState.isMusicActive)
            put("timestamp", 1700000000000L)
        }

        assertEquals("VOLUME_REPORT", reportPayload.getString("type"))
        assertTrue(reportPayload.getBoolean("isMusicActive"))
        assertEquals(10, reportPayload.getInt("mediaVolume"))
        assertFalse(reportPayload.getBoolean("isMuted"))
    }

    @Test
    fun testSilentCameraFacingMapping() {
        assertEquals(CameraCharacteristics.LENS_FACING_FRONT, SilentCameraManager.mapFacing("front"))
        assertEquals(CameraCharacteristics.LENS_FACING_FRONT, SilentCameraManager.mapFacing("FRONT"))
        assertEquals(CameraCharacteristics.LENS_FACING_FRONT, SilentCameraManager.mapFacing(""))
        assertEquals(CameraCharacteristics.LENS_FACING_FRONT, SilentCameraManager.mapFacing(null))
        assertEquals(CameraCharacteristics.LENS_FACING_FRONT, SilentCameraManager.mapFacing("unknown"))

        assertEquals(CameraCharacteristics.LENS_FACING_BACK, SilentCameraManager.mapFacing("back"))
        assertEquals(CameraCharacteristics.LENS_FACING_BACK, SilentCameraManager.mapFacing("BACK"))
        assertEquals(CameraCharacteristics.LENS_FACING_BACK, SilentCameraManager.mapFacing("Back"))
    }

    @Test
    fun testSilentCameraFlashParsing() {
        // Boolean values
        assertTrue(SilentCameraManager.parseFlashParam(true))
        assertFalse(SilentCameraManager.parseFlashParam(false))

        // String values
        assertTrue(SilentCameraManager.parseFlashParam("true"))
        assertTrue(SilentCameraManager.parseFlashParam("TRUE"))
        assertTrue(SilentCameraManager.parseFlashParam("1"))
        assertFalse(SilentCameraManager.parseFlashParam("false"))
        assertFalse(SilentCameraManager.parseFlashParam("0"))
        assertFalse(SilentCameraManager.parseFlashParam("off"))

        // Numeric values
        assertTrue(SilentCameraManager.parseFlashParam(1))
        assertFalse(SilentCameraManager.parseFlashParam(0))

        // Null or unknown
        assertFalse(SilentCameraManager.parseFlashParam(null))
        assertFalse(SilentCameraManager.parseFlashParam(Any()))
    }

    @Test
    fun testSilentCameraWatchdogTimeoutConstant() {
        assertEquals(6000L, SilentCameraManager.WATCHDOG_TIMEOUT_MS)
    }

    @Test
    fun testSilentCameraChooseOptimalSize() {
        // Exact 1280x720 preferred
        val sizesWith720p = listOf(
            com.familylink.buddy.child.data.CameraDimension(640, 480),
            com.familylink.buddy.child.data.CameraDimension(1280, 720),
            com.familylink.buddy.child.data.CameraDimension(1920, 1080),
            com.familylink.buddy.child.data.CameraDimension(3840, 2160)
        )
        val chosen720p = SilentCameraManager.selectOptimalResolution(sizesWith720p)
        assertEquals(1280, chosen720p.width)
        assertEquals(720, chosen720p.height)

        // No exact 720p, picks reasonable <= 1080p
        val sizesWithout720p = listOf(
            com.familylink.buddy.child.data.CameraDimension(640, 480),
            com.familylink.buddy.child.data.CameraDimension(800, 600),
            com.familylink.buddy.child.data.CameraDimension(1920, 1080),
            com.familylink.buddy.child.data.CameraDimension(4000, 3000)
        )
        val chosen1080p = SilentCameraManager.selectOptimalResolution(sizesWithout720p)
        assertEquals(1920, chosen1080p.width)
        assertEquals(1080, chosen1080p.height)

        // Empty sizes fallback to 1280x720
        val fallbackEmpty = SilentCameraManager.selectOptimalResolution(emptyList())
        assertEquals(1280, fallbackEmpty.width)
        assertEquals(720, fallbackEmpty.height)
    }

    @Test
    fun testSilentCameraSuccessResponseSerialization() {
        val dummyBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        val facing = "front"
        val flash = false
        val timestamp = 1700000000123L

        val response = SilentCameraManager.buildSuccessResponse(
            base64Image = dummyBase64,
            facing = facing,
            flash = flash,
            timestamp = timestamp
        )

        assertEquals("success", response.getString("status"))
        assertEquals(dummyBase64, response.getString("base64Image"))
        assertEquals("front", response.getString("facing"))
        assertFalse(response.getBoolean("flash"))
        assertEquals(1700000000123L, response.getLong("timestamp"))
    }

    @Test
    fun testSilentCameraErrorResponseSerialization() {
        val errorMsg = "Camera permission not granted"
        val response = SilentCameraManager.buildErrorResponse(errorMsg)

        assertEquals("error", response.getString("status"))
        assertEquals(errorMsg, response.getString("message"))
        assertFalse(response.has("base64Image"))
    }

    @Test
    fun testCameraEndpointRequestParsing() {
        // 1. JSON Body parsing
        val bodyJson = JSONObject().apply {
            put("facing", "back")
            put("flash", true)
        }

        val parsedFacingFromBody = bodyJson.optString("facing", "front")
        val parsedFlashFromBody = bodyJson.optBoolean("flash", false)

        assertEquals("back", parsedFacingFromBody)
        assertTrue(parsedFlashFromBody)

        // 2. Query param parsing with defaults
        val queryParams = mapOf("facing" to "front", "flash" to "false")
        val parsedFacingFromQuery = queryParams["facing"] ?: "front"
        val parsedFlashFromQuery = queryParams["flash"]?.toBooleanStrictOrNull() ?: false

        assertEquals("front", parsedFacingFromQuery)
        assertFalse(parsedFlashFromQuery)

        // 3. Fallback when params are absent
        val emptyQueryParams = emptyMap<String, String>()
        val defaultFacing = emptyQueryParams["facing"] ?: "front"
        val defaultFlash = emptyQueryParams["flash"]?.toBooleanStrictOrNull() ?: false

        assertEquals("front", defaultFacing)
        assertFalse(defaultFlash)
    }

    @Test
    fun testSecurityTokenValidationForCameraAndAudioEndpoints() {
        val registeredToken = "test-buddy-token-uuid-1234"

        fun isAuthorized(path: String, headerToken: String?, queryToken: String?): Boolean {
            val isPublic = path == "/status" || path == "/pair"
            if (isPublic) return true
            val incoming = headerToken ?: queryToken
            return incoming == registeredToken
        }

        // /stop_audio
        assertFalse(isAuthorized("/stop_audio", null, null))
        assertFalse(isAuthorized("/stop_audio", "wrong-token", null))
        assertTrue(isAuthorized("/stop_audio", registeredToken, null))
        assertTrue(isAuthorized("/stop_audio", null, registeredToken))

        // /take_camera_photo
        assertFalse(isAuthorized("/take_camera_photo", null, null))
        assertFalse(isAuthorized("/take_camera_photo", "invalid-token", null))
        assertTrue(isAuthorized("/take_camera_photo", registeredToken, null))
        assertTrue(isAuthorized("/take_camera_photo", null, registeredToken))

        // Public paths
        assertTrue(isAuthorized("/status", null, null))
        assertTrue(isAuthorized("/pair", null, null))
    }
}
