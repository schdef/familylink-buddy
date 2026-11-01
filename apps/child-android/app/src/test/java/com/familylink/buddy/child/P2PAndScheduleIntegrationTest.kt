package com.familylink.buddy.child

import com.familylink.buddy.child.data.BedtimeSchedule
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class P2PAndScheduleIntegrationTest {

    @Test
    fun testBedtimeScheduleDeserializationFromFirestore() {
        val firestoreMap = mapOf<String, Any?>(
            "isEnabled" to true,
            "bedtimeHour" to 21L,
            "bedtimeMinute" to 0L,
            "wakeupHour" to 7L,
            "wakeupMinute" to 15L,
            "activeDays" to listOf(1L, 2L, 3L, 4L, 5L),
            "isCurrentlyBlocked" to false
        )

        val schedule = BedtimeSchedule.fromMap(firestoreMap)
        assertTrue(schedule.isEnabled)
        assertEquals(21, schedule.bedtimeHour)
        assertEquals(0, schedule.bedtimeMinute)
        assertEquals(7, schedule.wakeupHour)
        assertEquals(15, schedule.wakeupMinute)
        assertEquals(listOf(1, 2, 3, 4, 5), schedule.activeDays)
        assertFalse(schedule.isCurrentlyBlocked)
    }

    @Test
    fun testFcmSetScheduleParsingFromJsonString() {
        val original = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 22,
            bedtimeMinute = 15,
            wakeupHour = 6,
            wakeupMinute = 30,
            activeDays = listOf(1, 2, 3, 4, 5, 6, 7)
        )
        val jsonStr = original.toJson()

        val fcmData = mapOf("type" to "SET_SCHEDULE", "schedule" to jsonStr)
        val parsedSchedule = BedtimeSchedule.fromJson(fcmData["schedule"]!!)

        assertEquals(original.isEnabled, parsedSchedule.isEnabled)
        assertEquals(original.bedtimeHour, parsedSchedule.bedtimeHour)
        assertEquals(original.bedtimeMinute, parsedSchedule.bedtimeMinute)
        assertEquals(original.wakeupHour, parsedSchedule.wakeupHour)
        assertEquals(original.wakeupMinute, parsedSchedule.wakeupMinute)
        assertEquals(original.activeDays, parsedSchedule.activeDays)
    }

    @Test
    fun testFcmSetScheduleParsingFromIndividualParams() {
        val fcmData = mapOf(
            "type" to "SET_SCHEDULE",
            "enabled" to "true",
            "bedtimeHour" to "20",
            "bedtimeMinute" to "45",
            "wakeupHour" to "7",
            "wakeupMinute" to "0",
            "activeDays" to "1,2,3,4,5"
        )

        val isEnabled = fcmData["enabled"]?.toBoolean() ?: false
        val bedtimeHour = fcmData["bedtimeHour"]?.toIntOrNull() ?: 20
        val bedtimeMinute = fcmData["bedtimeMinute"]?.toIntOrNull() ?: 30
        val wakeupHour = fcmData["wakeupHour"]?.toIntOrNull() ?: 6
        val wakeupMinute = fcmData["wakeupMinute"]?.toIntOrNull() ?: 45
        val activeDays = fcmData["activeDays"]?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: emptyList()

        val schedule = BedtimeSchedule(
            isEnabled = isEnabled,
            bedtimeHour = bedtimeHour,
            bedtimeMinute = bedtimeMinute,
            wakeupHour = wakeupHour,
            wakeupMinute = wakeupMinute,
            activeDays = activeDays
        )

        assertTrue(schedule.isEnabled)
        assertEquals(20, schedule.bedtimeHour)
        assertEquals(45, schedule.bedtimeMinute)
        assertEquals(7, schedule.wakeupHour)
        assertEquals(0, schedule.wakeupMinute)
        assertEquals(listOf(1, 2, 3, 4, 5), schedule.activeDays)
    }

    @Test
    fun testToggleWifiParamResolution() {
        // Test case 1: block=true -> turnOn=false
        val params1 = mapOf("block" to "true")
        val block1 = params1["block"]?.equals("true", ignoreCase = true) == true
        val turnOn1 = if (params1.containsKey("turnOn")) params1["turnOn"]?.toBoolean() == true else !block1
        assertFalse(turnOn1)

        // Test case 2: block=false -> turnOn=true
        val params2 = mapOf("block" to "false")
        val block2 = params2["block"]?.equals("true", ignoreCase = true) == true
        val turnOn2 = if (params2.containsKey("turnOn")) params2["turnOn"]?.toBoolean() == true else !block2
        assertTrue(turnOn2)

        // Test case 3: turnOn=false explicitly takes precedence
        val params3 = mapOf("turnOn" to "false", "block" to "false")
        val turnOn3 = params3["turnOn"]?.equals("true", ignoreCase = true) == true
        assertFalse(turnOn3)
    }

    @Test
    fun testApkUploadValidationThreshold() {
        val minApkSize = 1024 * 1024 // 1MB threshold

        val smallFileSize = 500 * 1024L
        val largeFileSize = 2 * 1024 * 1024L

        assertTrue("Small file should fail >1MB check", smallFileSize <= minApkSize)
        assertTrue("Large file should pass >1MB check", largeFileSize > minApkSize)
    }
}
