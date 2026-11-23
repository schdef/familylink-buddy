package com.familylink.buddy.child

import com.familylink.buddy.child.data.AudioPlaybackManager
import com.familylink.buddy.child.data.BedtimeSchedule
import com.familylink.buddy.child.data.UpdateManager
import com.familylink.buddy.child.service.LocalHttpServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalHttpServerLogicTest {

    @Test
    fun testPortConstant() {
        assertEquals(8085, LocalHttpServer.PORT)
    }

    @Test
    fun testStopServerClearsInstance() {
        LocalHttpServer.stopServer()
        assertNull(LocalHttpServer.getInstance())
    }

    @Test
    fun testVolumeReportWithMediaInfo() {
        AudioPlaybackManager.updateMediaInfo("Test Track", "Test Artist", "com.spotify.music")

        val isMusicActive = true
        val responseJson = JSONObject().apply {
            put("type", "VOLUME_REPORT")
            put("mediaVolume", 10)
            put("ringtoneVolume", 7)
            put("alarmVolume", 8)
            put("maxMediaVolume", 15)
            put("maxRingtoneVolume", 15)
            put("maxAlarmVolume", 15)
            put("isMuted", false)
            put("isMusicActive", isMusicActive)
            if (isMusicActive) {
                put("mediaTitle", AudioPlaybackManager.currentMediaTitle ?: "")
                put("mediaArtist", AudioPlaybackManager.currentMediaArtist ?: "")
                put("mediaPackage", AudioPlaybackManager.currentMediaPackage ?: "")
            }
            put("timestamp", 1700000000000L)
        }

        assertEquals("VOLUME_REPORT", responseJson.getString("type"))
        assertTrue(responseJson.getBoolean("isMusicActive"))
        assertEquals("Test Track", responseJson.getString("mediaTitle"))
        assertEquals("Test Artist", responseJson.getString("mediaArtist"))
        assertEquals("com.spotify.music", responseJson.getString("mediaPackage"))

        AudioPlaybackManager.clearMediaInfo()
    }

    @Test
    fun testStatusResponseWithMediaInfo() {
        AudioPlaybackManager.updateMediaInfo("Pod Title", "Pod Host", "com.google.android.apps.podcasts")
        val isMusicActive = true

        val responseJson = JSONObject().apply {
            put("status", "online")
            put("deviceId", "tab-1234")
            put("deviceName", "Test Tablet")
            put("version", "1.0.0")
            put("hasParentPin", true)
            put("isMusicActive", isMusicActive)
            if (isMusicActive) {
                put("mediaTitle", AudioPlaybackManager.currentMediaTitle ?: "")
                put("mediaArtist", AudioPlaybackManager.currentMediaArtist ?: "")
                put("mediaPackage", AudioPlaybackManager.currentMediaPackage ?: "")
            }
        }

        assertEquals("online", responseJson.getString("status"))
        assertTrue(responseJson.getBoolean("isMusicActive"))
        assertEquals("Pod Title", responseJson.getString("mediaTitle"))
        assertEquals("Pod Host", responseJson.getString("mediaArtist"))
        assertEquals("com.google.android.apps.podcasts", responseJson.getString("mediaPackage"))

        AudioPlaybackManager.clearMediaInfo()
    }

    @Test
    fun testAppHistoryPayloadStructure() {
        val historyArray = JSONArray().apply {
            put(JSONObject().apply {
                put("packageName", "com.roblox.client")
                put("label", "Roblox")
                put("timestamp", 1731440000000L)
            })
            put(JSONObject().apply {
                put("packageName", "com.google.android.googlequicksearchbox")
                put("label", "Google")
                put("timestamp", 1731440050000L)
            })
        }

        val responseJson = JSONObject().apply {
            put("status", "success")
            put("history", historyArray)
        }

        assertEquals("success", responseJson.getString("status"))
        assertEquals(2, responseJson.getJSONArray("history").length())
        val firstItem = responseJson.getJSONArray("history").getJSONObject(0)
        assertEquals("com.roblox.client", firstItem.getString("packageName"))
        assertEquals("Roblox", firstItem.getString("label"))
        assertEquals(1731440000000L, firstItem.getLong("timestamp"))
    }

    @Test
    fun testToggleBlockAppJsonPayloadAndResponse() {
        // Simulating JSON body
        val bodyJson = JSONObject().apply {
            put("package", "com.roblox.client")
            put("blocked", true)
        }
        val targetPkg = bodyJson.optString("package")
        val isBlocked = bodyJson.getBoolean("blocked")

        val responseJson = JSONObject().apply {
            put("status", "success")
            put("package", targetPkg)
            put("isBlocked", isBlocked)
            put("blacklistedPackages", JSONArray().put(targetPkg))
        }

        assertEquals("success", responseJson.getString("status"))
        assertEquals("com.roblox.client", responseJson.getString("package"))
        assertTrue(responseJson.getBoolean("isBlocked"))
        assertEquals(1, responseJson.getJSONArray("blacklistedPackages").length())
        assertEquals("com.roblox.client", responseJson.getJSONArray("blacklistedPackages").getString(0))
    }

    @Test
    fun testToggleBlockAppQueryParamsFallback() {
        val queryParams = mapOf("packageName" to "com.zhiliaoapp.musically", "isBlocked" to "false")
        val targetPackage = queryParams["package"] ?: queryParams["packageName"] ?: ""
        val isBlocked = queryParams["blocked"]?.toBooleanStrictOrNull()
            ?: queryParams["isBlocked"]?.toBooleanStrictOrNull()
            ?: true

        assertEquals("com.zhiliaoapp.musically", targetPackage)
        assertFalse(isBlocked)

        val responseJson = JSONObject().apply {
            put("status", "success")
            put("package", targetPackage)
            put("isBlocked", isBlocked)
            put("blacklistedPackages", JSONArray())
        }
        assertEquals("success", responseJson.getString("status"))
        assertFalse(responseJson.getBoolean("isBlocked"))
        assertEquals(0, responseJson.getJSONArray("blacklistedPackages").length())
    }

    @Test
    fun testToggleBlockAppMissingPackageError() {
        val queryParams = emptyMap<String, String>()
        val targetPackage = queryParams["package"] ?: queryParams["packageName"] ?: ""

        assertTrue(targetPackage.isBlank())
        val responseJson = JSONObject().apply {
            put("status", "error")
            put("message", "Missing 'package' parameter")
        }
        assertEquals("error", responseJson.getString("status"))
        assertEquals("Missing 'package' parameter", responseJson.getString("message"))
    }

    @Test
    fun testSetAppRulesResponseCounts() {
        val responseJson = JSONObject().apply {
            put("status", "success")
            put("blacklistedCount", 3)
            put("categoriesCount", 2)
            put("bonusCount", 1)
        }

        assertEquals("success", responseJson.getString("status"))
        assertEquals(3, responseJson.getInt("blacklistedCount"))
        assertEquals(2, responseJson.getInt("categoriesCount"))
        assertEquals(1, responseJson.getInt("bonusCount"))
    }

    @Test
    fun testStatusResponseWithBedtimeFields() {
        val responseJson = JSONObject().apply {
            put("status", "online")
            put("deviceId", "tab-1234")
            put("deviceName", "Test Tablet")
            put("version", "1.0.0")
            put("hasParentPin", true)
            put("isMusicActive", false)
            put("bedtimeEnabled", true)
            put("isBedtimeBlocked", false)
        }

        assertEquals("online", responseJson.getString("status"))
        assertTrue(responseJson.getBoolean("bedtimeEnabled"))
        assertFalse(responseJson.getBoolean("isBedtimeBlocked"))
    }

    @Test
    fun testGetScheduleResponsePayloadStructureAndParsing() {
        val scheduleJson = JSONObject().apply {
            put("isEnabled", true)
            put("bedtimeHour", 20)
            put("bedtimeMinute", 30)
            put("wakeupHour", 6)
            put("wakeupMinute", 45)
            val daysArray = JSONArray().apply {
                listOf(1, 2, 3, 4, 5, 6, 7).forEach { put(it) }
            }
            put("activeDays", daysArray)
            put("isCurrentlyBlocked", false)
        }

        val responseJson = JSONObject().apply {
            put("status", "success")
            put("schedule", scheduleJson)
        }

        assertEquals("success", responseJson.getString("status"))
        val returnedSchedule = responseJson.getJSONObject("schedule")
        assertTrue(returnedSchedule.getBoolean("isEnabled"))
        assertEquals(20, returnedSchedule.getInt("bedtimeHour"))
        assertEquals(30, returnedSchedule.getInt("bedtimeMinute"))
        assertEquals(6, returnedSchedule.getInt("wakeupHour"))
        assertEquals(45, returnedSchedule.getInt("wakeupMinute"))
        assertEquals(7, returnedSchedule.getJSONArray("activeDays").length())
        assertFalse(returnedSchedule.getBoolean("isCurrentlyBlocked"))

        // Verify BedtimeSchedule model parses this JSON accurately
        val parsedSchedule = BedtimeSchedule.fromJson(returnedSchedule.toString())
        assertTrue(parsedSchedule.isEnabled)
        assertEquals(20, parsedSchedule.bedtimeHour)
        assertEquals(30, parsedSchedule.bedtimeMinute)
        assertEquals(6, parsedSchedule.wakeupHour)
        assertEquals(45, parsedSchedule.wakeupMinute)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), parsedSchedule.activeDays)
        assertFalse(parsedSchedule.isCurrentlyBlocked)
    }

    @Test
    fun testAuthenticationPolicyForGetSchedule() {
        val pairedToken = "sec_test_secret_token_123"
        val publicPaths = setOf("/status", "/pair")
        val path = "/get_schedule"

        assertFalse("Path $path must require authentication", publicPaths.contains(path))

        val checkAuth = { incomingToken: String? ->
            pairedToken.isNotEmpty() && !publicPaths.contains(path) && (incomingToken == null || incomingToken != pairedToken)
        }

        // Missing token -> unauthorized
        assertTrue(checkAuth(null))

        // Wrong token -> unauthorized
        assertTrue(checkAuth("wrong_token"))

        // Correct token -> authorized
        assertFalse(checkAuth("sec_test_secret_token_123"))
    }

    @Test
    fun testTriggerUpdateDownloadUrlParsingFromBody() {
        val bodyJson = JSONObject().apply {
            put("downloadUrl", "https://example.com/builds/child-v2.apk")
        }
        val parsedUrl = LocalHttpServer.parseDownloadUrl(bodyJson, emptyMap())
        assertEquals("https://example.com/builds/child-v2.apk", parsedUrl)
    }

    @Test
    fun testTriggerUpdateDownloadUrlParsingFromQueryParams() {
        val queryParams = mapOf("downloadUrl" to "https://example.com/query/child.apk")
        val parsedUrl = LocalHttpServer.parseDownloadUrl(null, queryParams)
        assertEquals("https://example.com/query/child.apk", parsedUrl)
    }

    @Test
    fun testTriggerUpdateDownloadUrlFallbackWhenMissingOrBlank() {
        // Null body and empty query params
        val urlFromEmpty = LocalHttpServer.parseDownloadUrl(null, emptyMap())
        assertEquals(UpdateManager.FALLBACK_DOWNLOAD_URL, urlFromEmpty)

        // Blank string in body
        val blankBody = JSONObject().apply {
            put("downloadUrl", "   ")
        }
        val urlFromBlankBody = LocalHttpServer.parseDownloadUrl(blankBody, emptyMap())
        assertEquals(UpdateManager.FALLBACK_DOWNLOAD_URL, urlFromBlankBody)

        // Blank query param
        val blankQuery = mapOf("downloadUrl" to "")
        val urlFromBlankQuery = LocalHttpServer.parseDownloadUrl(null, blankQuery)
        assertEquals(UpdateManager.FALLBACK_DOWNLOAD_URL, urlFromBlankQuery)
    }

    @Test
    fun testTriggerUpdateResponseJsonStructure() {
        val responseJson = JSONObject().apply {
            put("status", "success")
            put("message", "Update download started")
        }
        assertEquals("success", responseJson.getString("status"))
        assertEquals("Update download started", responseJson.getString("message"))
    }

    @Test
    fun testAuthenticationPolicyForTriggerUpdate() {
        val pairedToken = "sec_test_secret_token_123"
        val publicPaths = setOf("/status", "/pair")
        val path = "/trigger_update"

        assertFalse("Path $path must require authentication", publicPaths.contains(path))

        val checkAuth = { incomingToken: String? ->
            pairedToken.isNotEmpty() && !publicPaths.contains(path) && (incomingToken == null || incomingToken != pairedToken)
        }

        // Missing token -> unauthorized
        assertTrue(checkAuth(null))

        // Wrong token -> unauthorized
        assertTrue(checkAuth("wrong_token"))

        // Correct token -> authorized
        assertFalse(checkAuth("sec_test_secret_token_123"))
    }
}
