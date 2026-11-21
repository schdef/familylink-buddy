package com.familylink.buddy.child

import com.familylink.buddy.child.data.UpdateManager
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateManagerLogicTest {

    @Test
    fun testIsVersionNewerSemver() {
        // Newer versions
        assertTrue(UpdateManager.isVersionNewer("v1.2.0", "1.1.0"))
        assertTrue(UpdateManager.isVersionNewer("1.1.1", "1.1.0"))
        assertTrue(UpdateManager.isVersionNewer("2.0.0", "1.9.9"))
        assertTrue(UpdateManager.isVersionNewer("v1.1.2", "v1.1.1"))

        // Same versions
        assertFalse(UpdateManager.isVersionNewer("1.1.0", "1.1.0"))
        assertFalse(UpdateManager.isVersionNewer("v1.1.0", "1.1.0"))
        assertFalse(UpdateManager.isVersionNewer("1.1.0", "v1.1.0"))

        // Older versions
        assertFalse(UpdateManager.isVersionNewer("1.0.9", "1.1.0"))
        assertFalse(UpdateManager.isVersionNewer("v1.0.0", "1.1.0"))

        // Invalid or empty strings
        assertFalse(UpdateManager.isVersionNewer("", "1.1.0"))
        assertFalse(UpdateManager.isVersionNewer("abc", "1.1.0"))
        assertFalse(UpdateManager.isVersionNewer("1.2.0", ""))
    }

    @Test
    fun testAssetUrlParsingFromJson() {
        val json = JSONObject().apply {
            put("tag_name", "v1.2.0")
            put("name", "Release 1.2.0")
            put("body", "Bug fixes and performance improvements")
            val assetsArray = JSONArray().apply {
                put(JSONObject().apply {
                    put("name", "parent-app-release.apk")
                    put("browser_download_url", "https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/parent-app-release.apk")
                })
                put(JSONObject().apply {
                    put("name", "child-app-release.apk")
                    put("browser_download_url", "https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/child-app-release.apk")
                })
            }
            put("assets", assetsArray)
        }

        val assets = json.optJSONArray("assets")
        var downloadUrl = ""
        if (assets != null) {
            for (i in 0 until assets.length()) {
                val asset = assets.getJSONObject(i)
                val assetName = asset.optString("name", "")
                if (assetName.equals("child-app-release.apk", ignoreCase = true)) {
                    downloadUrl = asset.optString("browser_download_url", "")
                    break
                }
            }
        }

        assertEquals("https://github.com/schdef/familylink-buddy/releases/download/v1.2.0/child-app-release.apk", downloadUrl)
    }

    @Test
    fun testFallbackUrlUsedWhenNoAssetMatches() {
        val json = JSONObject().apply {
            put("tag_name", "v1.2.0")
            put("assets", JSONArray())
        }

        val assets = json.optJSONArray("assets")
        var downloadUrl = ""
        if (assets != null) {
            for (i in 0 until assets.length()) {
                val asset = assets.getJSONObject(i)
                if (asset.optString("name").equals("child-app-release.apk", ignoreCase = true)) {
                    downloadUrl = asset.optString("browser_download_url")
                }
            }
        }
        if (downloadUrl.isBlank()) {
            downloadUrl = UpdateManager.FALLBACK_DOWNLOAD_URL
        }

        assertEquals(UpdateManager.FALLBACK_DOWNLOAD_URL, downloadUrl)
    }
}
