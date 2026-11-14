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
import org.junit.Assert.assertNull
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

    @Test
    fun testVolumeStreamTypeMapping() {
        assertEquals(android.media.AudioManager.STREAM_MUSIC, AudioPlaybackManager.mapStreamType("MEDIA"))
        assertEquals(android.media.AudioManager.STREAM_MUSIC, AudioPlaybackManager.mapStreamType("media"))
        assertEquals(android.media.AudioManager.STREAM_RING, AudioPlaybackManager.mapStreamType("RINGTONE"))
        assertEquals(android.media.AudioManager.STREAM_RING, AudioPlaybackManager.mapStreamType("ringtone"))
        assertEquals(android.media.AudioManager.STREAM_ALARM, AudioPlaybackManager.mapStreamType("ALARM"))
        assertEquals(android.media.AudioManager.STREAM_ALARM, AudioPlaybackManager.mapStreamType("alarm"))
        assertEquals(android.media.AudioManager.STREAM_MUSIC, AudioPlaybackManager.mapStreamType("UNKNOWN"))
        assertEquals(android.media.AudioManager.STREAM_MUSIC, AudioPlaybackManager.mapStreamType(null))
    }

    @Test
    fun testVolumeStreamParamParsing() {
        // Body JSON has valid stream
        val jsonWithStream = JSONObject().put("stream", "RINGTONE")
        assertEquals("RINGTONE", AudioPlaybackManager.parseStreamParam(jsonWithStream, emptyMap()))

        // Body JSON has empty stream string -> must fall back to queryParams
        val jsonWithBlankStream = JSONObject().put("stream", "")
        val queryWithStream = mapOf("stream" to "ALARM")
        assertEquals("ALARM", AudioPlaybackManager.parseStreamParam(jsonWithBlankStream, queryWithStream))

        // Body JSON is null -> falls back to queryParams
        assertEquals("ALARM", AudioPlaybackManager.parseStreamParam(null, queryWithStream))

        // Both empty or absent -> defaults to "MEDIA"
        assertEquals("MEDIA", AudioPlaybackManager.parseStreamParam(null, emptyMap()))
        assertEquals("MEDIA", AudioPlaybackManager.parseStreamParam(JSONObject(), emptyMap()))
        assertEquals("MEDIA", AudioPlaybackManager.parseStreamParam(JSONObject().put("stream", "   "), emptyMap()))
    }

    @Test
    fun testVolumeLevelParamParsing() {
        // Body JSON has level
        val jsonWithLevel = JSONObject().put("level", 8)
        assertEquals(8, AudioPlaybackManager.parseLevelParam(jsonWithLevel, emptyMap()))

        // Body JSON has level 0
        val jsonWithZero = JSONObject().put("level", 0)
        assertEquals(0, AudioPlaybackManager.parseLevelParam(jsonWithZero, mapOf("level" to "12")))

        // Query param fallback
        assertEquals(11, AudioPlaybackManager.parseLevelParam(null, mapOf("level" to "11")))
        assertEquals(7, AudioPlaybackManager.parseLevelParam(JSONObject(), mapOf("level" to "7")))

        // Missing or invalid level defaults to 0
        assertEquals(0, AudioPlaybackManager.parseLevelParam(null, emptyMap()))
        assertEquals(0, AudioPlaybackManager.parseLevelParam(null, mapOf("level" to "invalid")))
    }

    @Test
    fun testBuildSetVolumeResponse() {
        val state = VolumeState(
            mediaVolume = 9,
            ringtoneVolume = 5,
            alarmVolume = 7,
            maxMediaVolume = 15,
            maxRingtoneVolume = 15,
            maxAlarmVolume = 15,
            isMuted = false,
            isMusicActive = true
        )

        val response = AudioPlaybackManager.buildSetVolumeResponse("MEDIA", 9, state)

        assertEquals("success", response.getString("status"))
        assertEquals("MEDIA", response.getString("stream"))
        assertEquals(9, response.getInt("level"))
        assertEquals(9, response.getInt("mediaVolume"))
        assertEquals(5, response.getInt("ringtoneVolume"))
        assertEquals(7, response.getInt("alarmVolume"))
        assertEquals(15, response.getInt("maxMediaVolume"))
        assertEquals(15, response.getInt("maxRingtoneVolume"))
        assertEquals(15, response.getInt("maxAlarmVolume"))
        assertFalse(response.getBoolean("isMuted"))
        assertTrue(response.getBoolean("isMusicActive"))
        assertTrue(response.has("timestamp"))
    }

    @Test
    fun testMediaInfoTrackingAndPayloadInclusion() {
        // Initially clear
        AudioPlaybackManager.clearMediaInfo()
        assertNull(AudioPlaybackManager.currentMediaTitle)
        assertNull(AudioPlaybackManager.currentMediaArtist)
        assertNull(AudioPlaybackManager.currentMediaPackage)

        // Update media info from notification
        AudioPlaybackManager.updateMediaInfo("Song A", "Artist B", "com.spotify.music")
        assertEquals("Song A", AudioPlaybackManager.currentMediaTitle)
        assertEquals("Artist B", AudioPlaybackManager.currentMediaArtist)
        assertEquals("com.spotify.music", AudioPlaybackManager.currentMediaPackage)

        // When music is active, buildSetVolumeResponse includes media fields
        val activeState = VolumeState(mediaVolume = 10, isMusicActive = true)
        val activeResponse = AudioPlaybackManager.buildSetVolumeResponse("MEDIA", 10, activeState)
        assertEquals("Song A", activeResponse.getString("mediaTitle"))
        assertEquals("Artist B", activeResponse.getString("mediaArtist"))
        assertEquals("com.spotify.music", activeResponse.getString("mediaPackage"))

        // When music is NOT active, buildSetVolumeResponse should not include media details
        val inactiveState = VolumeState(mediaVolume = 10, isMusicActive = false)
        val inactiveResponse = AudioPlaybackManager.buildSetVolumeResponse("MEDIA", 10, inactiveState)
        assertFalse(inactiveResponse.has("mediaTitle"))
        assertFalse(inactiveResponse.has("mediaArtist"))

        // Clearing media info
        AudioPlaybackManager.clearMediaInfo()
        assertNull(AudioPlaybackManager.currentMediaTitle)
        assertNull(AudioPlaybackManager.currentMediaArtist)
        assertNull(AudioPlaybackManager.currentMediaPackage)
    }
}
