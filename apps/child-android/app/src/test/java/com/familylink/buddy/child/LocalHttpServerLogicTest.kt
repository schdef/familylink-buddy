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
}
