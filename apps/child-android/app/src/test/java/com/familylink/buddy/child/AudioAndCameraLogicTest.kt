package com.familylink.buddy.child

import android.hardware.camera2.CameraCharacteristics
import android.media.session.PlaybackState
import android.util.Size
import com.familylink.buddy.child.data.AudioPlaybackManager
import com.familylink.buddy.child.data.SilentCameraManager
import com.familylink.buddy.child.data.VolumeState
import com.familylink.buddy.child.service.ChatNotificationListenerService
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

    @Test
    fun testTrackChangeDetection() {
        AudioPlaybackManager.clearMediaInfo()

        // 1. Initial track playback: Song A
        val initialTime = System.currentTimeMillis()
        AudioPlaybackManager.updateMediaInfo("Song A", "Artist A", "com.spotify.music")
        assertEquals("Song A", AudioPlaybackManager.currentMediaTitle)
        assertEquals("Artist A", AudioPlaybackManager.currentMediaArtist)
        assertEquals("com.spotify.music", AudioPlaybackManager.currentMediaPackage)
        assertTrue(AudioPlaybackManager.lastMediaUpdateTime >= initialTime)

        // 2. Track transition: next song (Song B) starts playing
        val nextTime = System.currentTimeMillis()
        AudioPlaybackManager.updateMediaInfo("Song B", "Artist B", "com.spotify.music")
        assertEquals("Song B", AudioPlaybackManager.currentMediaTitle)
        assertEquals("Artist B", AudioPlaybackManager.currentMediaArtist)
        assertEquals("com.spotify.music", AudioPlaybackManager.currentMediaPackage)
        assertTrue(AudioPlaybackManager.lastMediaUpdateTime >= nextTime)

        // 3. Controller selection during track transition states (STATE_BUFFERING, STATE_SKIPPING_TO_NEXT)
        val spotifyBuffering = AudioPlaybackManager.PlaybackControllerInfo(
            packageName = "com.spotify.music",
            playbackState = PlaybackState.STATE_BUFFERING,
            title = "Song B",
            artist = "Artist B"
        )
        val backgroundIdleApp = AudioPlaybackManager.PlaybackControllerInfo(
            packageName = "com.google.android.apps.podcasts",
            playbackState = PlaybackState.STATE_PAUSED,
            title = "Old Podcast",
            artist = "Old Host"
        )

        // Verify that controller matching currentMediaPackage is prioritized when buffering
        val target = AudioPlaybackManager.selectTargetControllerInfo(
            controllers = listOf(backgroundIdleApp, spotifyBuffering),
            currentPackage = "com.spotify.music",
            isAudioActive = true
        )
        assertNotNull(target)
        assertEquals("com.spotify.music", target?.packageName)
        assertEquals("Song B", target?.title)

        // 4. Verify support for all active transition states
        assertTrue(AudioPlaybackManager.ACTIVE_PLAYBACK_STATES.contains(PlaybackState.STATE_PLAYING))
        assertTrue(AudioPlaybackManager.ACTIVE_PLAYBACK_STATES.contains(PlaybackState.STATE_BUFFERING))
        assertTrue(AudioPlaybackManager.ACTIVE_PLAYBACK_STATES.contains(PlaybackState.STATE_SKIPPING_TO_NEXT))
        assertTrue(AudioPlaybackManager.ACTIVE_PLAYBACK_STATES.contains(PlaybackState.STATE_FAST_FORWARDING))
        assertFalse(AudioPlaybackManager.ACTIVE_PLAYBACK_STATES.contains(PlaybackState.STATE_PAUSED))
        assertFalse(AudioPlaybackManager.ACTIVE_PLAYBACK_STATES.contains(PlaybackState.STATE_STOPPED))

        AudioPlaybackManager.clearMediaInfo()
    }

    @Test
    fun testDisplayTitleAndDisplaySubtitleFallbacks() {
        // 1. Primary title present -> should use primary title
        val title1 = AudioPlaybackManager.extractTitle(
            titleString = "Primary Song Title",
            displayTitleString = "Fallback Display Title"
        )
        assertEquals("Primary Song Title", title1)

        // 2. Primary title null/blank -> fallback to displayTitle
        val title2 = AudioPlaybackManager.extractTitle(
            titleString = null,
            displayTitleString = "Fallback Display Title"
        )
        assertEquals("Fallback Display Title", title2)

        val title3 = AudioPlaybackManager.extractTitle(
            titleString = "   ",
            displayTitleString = "Fallback Display Title"
        )
        assertEquals("Fallback Display Title", title3)

        // 3. String titles null -> fallback to CharSequence text
        val title4 = AudioPlaybackManager.extractTitle(
            titleString = null,
            displayTitleString = null,
            titleText = "CharSequence Title"
        )
        assertEquals("CharSequence Title", title4)

        // 4. All titles null/empty -> returns null
        assertNull(AudioPlaybackManager.extractTitle(null, null, null, null))
        assertNull(AudioPlaybackManager.extractTitle("", "  ", "", "   "))

        // 5. Primary artist present -> should use primary artist
        val artist1 = AudioPlaybackManager.extractArtist(
            artistString = "Primary Artist",
            albumArtistString = "Album Artist",
            displaySubtitleString = "Display Subtitle",
            authorString = "Author"
        )
        assertEquals("Primary Artist", artist1)

        // 6. Primary artist missing -> fallback to albumArtist
        val artist2 = AudioPlaybackManager.extractArtist(
            artistString = null,
            albumArtistString = "Album Artist",
            displaySubtitleString = "Display Subtitle",
            authorString = "Author"
        )
        assertEquals("Album Artist", artist2)

        // 7. Primary & album artist missing -> fallback to displaySubtitle
        val artist3 = AudioPlaybackManager.extractArtist(
            artistString = "  ",
            albumArtistString = null,
            displaySubtitleString = "Display Subtitle",
            authorString = "Author"
        )
        assertEquals("Display Subtitle", artist3)

        // 8. Primary, album, subtitle missing -> fallback to author
        val artist4 = AudioPlaybackManager.extractArtist(
            artistString = null,
            albumArtistString = null,
            displaySubtitleString = null,
            authorString = "Audiobook Author"
        )
        assertEquals("Audiobook Author", artist4)

        // 9. All artist strings missing -> fallback to artistText CharSequence
        val artist5 = AudioPlaybackManager.extractArtist(
            artistString = null,
            albumArtistString = null,
            displaySubtitleString = null,
            authorString = null,
            artistText = "CharSequence Artist"
        )
        assertEquals("CharSequence Artist", artist5)

        // 10. All null/blank -> returns null
        assertNull(AudioPlaybackManager.extractArtist(null, null, null, null, null))
        assertNull(AudioPlaybackManager.extractArtist(" ", "", "  ", "   ", ""))
    }

    @Test
    fun testAvoidingNonMediaNotificationOverwrite() {
        // 1. Generic battery alert (non-media) -> MUST NOT be identified as media notification
        val isBatteryAlertMedia = ChatNotificationListenerService.isMediaNotification(
            category = "sys",
            hasMediaSessionExtra = false,
            template = null,
            actionTitles = listOf("Turn on Battery Saver")
        )
        assertFalse("Battery warning should never be identified as media", isBatteryAlertMedia)

        // 2. Download complete alert (non-media) -> MUST NOT be identified as media
        val isDownloadAlertMedia = ChatNotificationListenerService.isMediaNotification(
            category = null,
            hasMediaSessionExtra = false,
            template = null,
            actionTitles = listOf("Open file")
        )
        assertFalse("Download alert should never be identified as media", isDownloadAlertMedia)

        // 3. Regular chat message -> MUST NOT be identified as media
        val isChatMedia = ChatNotificationListenerService.isMediaNotification(
            category = "msg",
            hasMediaSessionExtra = false,
            template = "android.app.Notification\$MessagingStyle",
            actionTitles = listOf("Reply", "Mark as read")
        )
        assertFalse("Chat notification should not be identified as media", isChatMedia)

        // 4. Media notification with EXTRA_MEDIA_SESSION -> MUST be identified as media
        val isSessionMedia = ChatNotificationListenerService.isMediaNotification(
            category = null,
            hasMediaSessionExtra = true,
            template = null,
            actionTitles = null
        )
        assertTrue("Media session extra must identify as media", isSessionMedia)

        // 5. Media notification with MediaStyle template -> MUST be identified as media
        val isTemplateMedia = ChatNotificationListenerService.isMediaNotification(
            category = null,
            hasMediaSessionExtra = false,
            template = "androidx.media.app.NotificationCompat\$MediaStyle",
            actionTitles = null
        )
        assertTrue("MediaStyle template must identify as media", isTemplateMedia)

        // 6. Media notification with CATEGORY_TRANSPORT -> MUST be identified as media
        val isTransportMedia = ChatNotificationListenerService.isMediaNotification(
            category = "transport",
            hasMediaSessionExtra = false,
            template = null,
            actionTitles = null
        )
        assertTrue("CATEGORY_TRANSPORT must identify as media", isTransportMedia)

        // 7. Notification with transport action ("Pause", "Play", "Next", "Skip") -> MUST be identified as media
        val isActionMedia = ChatNotificationListenerService.isMediaNotification(
            category = null,
            hasMediaSessionExtra = false,
            template = null,
            actionTitles = listOf("Previous", "Pause", "Next")
        )
        assertTrue("Transport actions must identify as media", isActionMedia)
    }

    @Test
    fun testPlaybackCleanupOnStop() {
        AudioPlaybackManager.clearMediaInfo()
        AudioPlaybackManager.updateMediaInfo("Track 1", "Artist 1", "com.spotify.music")
        assertEquals("Track 1", AudioPlaybackManager.currentMediaTitle)
        assertEquals("Artist 1", AudioPlaybackManager.currentMediaArtist)
        assertEquals("com.spotify.music", AudioPlaybackManager.currentMediaPackage)

        // Clear media info
        AudioPlaybackManager.clearMediaInfo()
        assertNull(AudioPlaybackManager.currentMediaTitle)
        assertNull(AudioPlaybackManager.currentMediaArtist)
        assertNull(AudioPlaybackManager.currentMediaPackage)

        // Notification removal logic simulation
        AudioPlaybackManager.updateMediaInfo("Podcast Episode 42", "Host X", "com.google.android.apps.podcasts")

        fun onNotificationRemovedSim(pkg: String, isMusicActive: Boolean) {
            if (pkg == AudioPlaybackManager.currentMediaPackage && !isMusicActive) {
                AudioPlaybackManager.clearMediaInfo()
            }
        }

        // Notification from a different package removed -> media info should NOT be cleared
        onNotificationRemovedSim("com.whatsapp", isMusicActive = false)
        assertEquals("Podcast Episode 42", AudioPlaybackManager.currentMediaTitle)

        // Notification from podcast app removed while music is still active -> media info remains
        onNotificationRemovedSim("com.google.android.apps.podcasts", isMusicActive = true)
        assertEquals("Podcast Episode 42", AudioPlaybackManager.currentMediaTitle)

        // Notification from podcast app removed when music is stopped -> media info IS cleared
        onNotificationRemovedSim("com.google.android.apps.podcasts", isMusicActive = false)
        assertNull(AudioPlaybackManager.currentMediaTitle)
        assertNull(AudioPlaybackManager.currentMediaArtist)
        assertNull(AudioPlaybackManager.currentMediaPackage)
    }

    @Test
    fun testMediaNotificationExtractionAndFilteringLogic() {
        AudioPlaybackManager.clearMediaInfo()

        fun shouldUpdateMedia(
            pkg: String,
            hasMediaSession: Boolean,
            isTransport: Boolean,
            template: String?,
            actionTitles: List<String>?,
            supportedChatPackages: Set<String>
        ): Boolean {
            val isChatApp = supportedChatPackages.contains(pkg)
            if (isChatApp) return false
            return ChatNotificationListenerService.isMediaNotification(
                category = if (isTransport) "transport" else null,
                hasMediaSessionExtra = hasMediaSession,
                template = template,
                actionTitles = actionTitles
            )
        }

        val chatPackages = setOf("com.whatsapp", "org.telegram.messenger", "com.google.android.apps.messaging")

        // 1. WhatsApp notification while music is playing -> must NOT update media
        assertFalse(shouldUpdateMedia("com.whatsapp", hasMediaSession = false, isTransport = false, template = null, actionTitles = null, supportedChatPackages = chatPackages))

        // 2. Spotify media session notification -> MUST update media
        assertTrue(shouldUpdateMedia("com.spotify.music", hasMediaSession = true, isTransport = true, template = null, actionTitles = null, supportedChatPackages = chatPackages))

        // 3. YouTube Music transport notification -> MUST update media
        assertTrue(shouldUpdateMedia("com.google.android.apps.youtube.music", hasMediaSession = false, isTransport = true, template = null, actionTitles = null, supportedChatPackages = chatPackages))

        // 4. Background podcast active playback with media template -> MUST update media
        assertTrue(shouldUpdateMedia("com.bip.podcasts", hasMediaSession = false, isTransport = false, template = "androidx.media.app.NotificationCompat\$MediaStyle", actionTitles = null, supportedChatPackages = chatPackages))

        // 5. Generic battery warning while music is active -> MUST NOT update media
        assertFalse(shouldUpdateMedia("android", hasMediaSession = false, isTransport = false, template = null, actionTitles = listOf("Battery Saver"), supportedChatPackages = chatPackages))

        // Updating media info
        AudioPlaybackManager.updateMediaInfo("Starboy", "The Weeknd", "com.spotify.music")
        assertEquals("Starboy", AudioPlaybackManager.currentMediaTitle)
        assertEquals("The Weeknd", AudioPlaybackManager.currentMediaArtist)
        assertEquals("com.spotify.music", AudioPlaybackManager.currentMediaPackage)

        // Notification removed for current package when audio is inactive -> clears media
        fun onNotificationRemovedSim(pkg: String, isMusicActive: Boolean) {
            if (pkg == AudioPlaybackManager.currentMediaPackage && !isMusicActive) {
                AudioPlaybackManager.clearMediaInfo()
            }
        }

        // Removed from a different package -> stays
        onNotificationRemovedSim("com.whatsapp", isMusicActive = false)
        assertEquals("Starboy", AudioPlaybackManager.currentMediaTitle)

        // Removed from Spotify while music is still active -> stays
        onNotificationRemovedSim("com.spotify.music", isMusicActive = true)
        assertEquals("Starboy", AudioPlaybackManager.currentMediaTitle)

        // Removed from Spotify when music stopped -> cleared!
        onNotificationRemovedSim("com.spotify.music", isMusicActive = false)
        assertNull(AudioPlaybackManager.currentMediaTitle)
    }
}
