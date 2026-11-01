package com.familylink.buddy.child

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ScreenshotLogicTest {

    @Test
    fun testHttpServerSuccessPayloadSerialization() {
        val dummyBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        val foregroundApp = "YouTube"
        val foregroundPackage = "com.google.android.youtube"
        val timestamp = System.currentTimeMillis()

        val json = JSONObject().apply {
            put("status", "success")
            put("base64Image", dummyBase64)
            put("foregroundApp", foregroundApp)
            put("foregroundPackage", foregroundPackage)
            put("timestamp", timestamp)
        }

        val jsonString = json.toString()
        val parsed = JSONObject(jsonString)

        assertEquals("success", parsed.getString("status"))
        assertEquals(dummyBase64, parsed.getString("base64Image"))
        assertEquals(foregroundApp, parsed.getString("foregroundApp"))
        assertEquals(foregroundPackage, parsed.getString("foregroundPackage"))
        assertEquals(timestamp, parsed.getLong("timestamp"))
    }

    @Test
    fun testHttpServerCloseAppPayloadSerialization() {
        val json = JSONObject().apply {
            put("status", "success")
            put("message", "Foreground app closed")
        }

        val jsonString = json.toString()
        val parsed = JSONObject(jsonString)

        assertEquals("success", parsed.getString("status"))
        assertEquals("Foreground app closed", parsed.getString("message"))
    }

    @Test
    fun testHttpServerErrorPayloadSerialization() {
        val errorMessage = "Accessibility Service is not connected"
        val json = JSONObject().apply {
            put("status", "error")
            put("message", errorMessage)
        }

        val jsonString = json.toString()
        val parsed = JSONObject(jsonString)

        assertEquals("error", parsed.getString("status"))
        assertEquals(errorMessage, parsed.getString("message"))
        assertFalse(parsed.has("base64Image"))
    }

    @Test
    fun testFirestoreScreenshotDocumentPayload() {
        val dummyBase64 = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="
        val foregroundApp = "Brawl Stars"
        val foregroundPackage = "com.supercell.brawlstars"
        val isoTimestamp = Instant.now().toString()
        val deviceModel = "Pixel 7 Pro"

        val docData = hashMapOf<String, Any>(
            "base64Image" to dummyBase64,
            "foregroundApp" to foregroundApp,
            "foregroundPackage" to foregroundPackage,
            "capturedAt" to isoTimestamp,
            "device" to deviceModel
        )

        assertEquals(dummyBase64, docData["base64Image"])
        assertEquals(foregroundApp, docData["foregroundApp"])
        assertEquals(foregroundPackage, docData["foregroundPackage"])
        assertEquals(isoTimestamp, docData["capturedAt"])
        assertEquals(deviceModel, docData["device"])
        assertTrue((docData["capturedAt"] as String).matches(Regex("^\\d{4}-\\d{2}-\\d{2}T.*Z$")))
    }

    @Test
    fun testCloseAppCommandProcessingAndDeduplication() {
        var lastCloseAppTimestamp = 0L
        var closeExecutedCount = 0

        fun processCloseApp(data: Map<String, Any?>): Boolean {
            val closeAppCommand = data["closeAppCommand"] as? Map<*, *> ?: return false
            val timestamp = when (val ts = closeAppCommand["timestamp"]) {
                is Number -> ts.toLong()
                is String -> ts.toLongOrNull() ?: 0L
                else -> 0L
            }
            if (timestamp > lastCloseAppTimestamp) {
                lastCloseAppTimestamp = timestamp
                closeExecutedCount++
                return true
            }
            return false
        }

        // 1. Initial command
        val cmd1 = mapOf<String, Any?>("closeAppCommand" to mapOf("timestamp" to 1700000000000L))
        assertTrue(processCloseApp(cmd1))
        assertEquals(1, closeExecutedCount)
        assertEquals(1700000000000L, lastCloseAppTimestamp)

        // 2. Duplicate snapshot
        assertFalse(processCloseApp(cmd1))
        assertEquals(1, closeExecutedCount)

        // 3. Stale command with earlier timestamp
        val staleCmd = mapOf<String, Any?>("closeAppCommand" to mapOf("timestamp" to 1699999999000L))
        assertFalse(processCloseApp(staleCmd))
        assertEquals(1, closeExecutedCount)

        // 4. Newer command
        val cmd2 = mapOf<String, Any?>("closeAppCommand" to mapOf("timestamp" to 1700000005000L))
        assertTrue(processCloseApp(cmd2))
        assertEquals(2, closeExecutedCount)
        assertEquals(1700000005000L, lastCloseAppTimestamp)
    }

    @Test
    fun testForegroundAppLabelFallbackLogic() {
        fun resolveFallbackLabel(rawPackage: String, appPkg: String): String {
            return when {
                rawPackage.contains("launcher", ignoreCase = true) ||
                rawPackage.contains("nexuslauncher", ignoreCase = true) ||
                rawPackage.contains("trebuchet", ignoreCase = true) ||
                rawPackage.contains("quickstep", ignoreCase = true) -> "Startbildschirm"
                rawPackage.contains("systemui", ignoreCase = true) -> "System UI"
                rawPackage == appPkg -> "FamilyLink Buddy"
                else -> rawPackage
            }
        }

        val appPkg = "com.familylink.buddy.child"
        assertEquals("Startbildschirm", resolveFallbackLabel("com.google.android.apps.nexuslauncher", appPkg))
        assertEquals("Startbildschirm", resolveFallbackLabel("com.android.launcher3", appPkg))
        assertEquals("FamilyLink Buddy", resolveFallbackLabel("com.familylink.buddy.child", appPkg))
        assertEquals("System UI", resolveFallbackLabel("com.android.systemui", appPkg))
        assertEquals("com.roblox.client", resolveFallbackLabel("com.roblox.client", appPkg))
    }

    @Test
    fun testScreenshotRequestParsingAndDeduplication() {
        var lastRequestId: String? = null

        fun processRequest(data: Map<String, Any?>): String? {
            val requestMap = data["screenshotRequest"] as? Map<*, *> ?: return null
            val requestId = (requestMap["requestId"] ?: requestMap["id"])?.toString()
            if (!requestId.isNullOrEmpty() && requestId != lastRequestId) {
                lastRequestId = requestId
                return requestId
            }
            return null
        }

        // 1. Initial request with 'requestId'
        val data1 = mapOf<String, Any?>(
            "screenshotRequest" to mapOf("requestId" to "req_001", "requestedAt" to 123456789L)
        )
        val result1 = processRequest(data1)
        assertEquals("req_001", result1)
        assertEquals("req_001", lastRequestId)

        // 2. Duplicate snapshot received from Firestore
        val result2 = processRequest(data1)
        assertEquals(null, result2) // Deduplicated, ignored

        // 3. Request with fallback 'id' field
        val data3 = mapOf<String, Any?>(
            "screenshotRequest" to mapOf("id" to "req_002", "trigger" to "manual")
        )
        val result3 = processRequest(data3)
        assertEquals("req_002", result3)
        assertEquals("req_002", lastRequestId)

        // 4. Missing request or invalid format
        val data4 = mapOf<String, Any?>("volumeCommand" to mapOf("stream" to "MEDIA"))
        val result4 = processRequest(data4)
        assertEquals(null, result4)
    }

    @Test
    fun testAspectRatioAndScalingDimensionCalculation() {
        fun calculateScaledDimensions(width: Int, height: Int, maxAllowedWidth: Int): Pair<Int, Int> {
            return if (width > maxAllowedWidth) {
                val ratio = maxAllowedWidth.toFloat() / width
                val targetHeight = (height * ratio).toInt()
                Pair(maxAllowedWidth, targetHeight)
            } else {
                Pair(width, height)
            }
        }

        // Full HD landscape (1920x1080) -> scaled to 1280x720
        val (scaledW1, scaledH1) = calculateScaledDimensions(1920, 1080, 1280)
        assertEquals(1280, scaledW1)
        assertEquals(720, scaledH1)

        // Tall smartphone portrait (1440x3120) -> scaled to 1280x2773
        val (scaledW2, scaledH2) = calculateScaledDimensions(1440, 3120, 1280)
        assertEquals(1280, scaledW2)
        assertEquals(2773, scaledH2)

        // Smaller phone display (720x1280) -> untouched
        val (scaledW3, scaledH3) = calculateScaledDimensions(720, 1280, 1280)
        assertEquals(720, scaledW3)
        assertEquals(1280, scaledH3)
    }
}
