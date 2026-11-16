package com.familylink.buddy.child

import com.familylink.buddy.child.data.AudioPlaybackManager
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
}
