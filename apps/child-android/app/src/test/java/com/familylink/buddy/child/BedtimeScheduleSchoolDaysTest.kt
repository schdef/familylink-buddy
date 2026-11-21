package com.familylink.buddy.child

import com.familylink.buddy.child.data.BedtimeSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class BedtimeScheduleSchoolDaysTest {

    private fun createCal(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0): Calendar {
        return Calendar.getInstance().apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, second)
            set(Calendar.MILLISECOND, 0)
        }
    }

    @Test
    fun testDefaultActiveDaysIsEveryDay() {
        val schedule = BedtimeSchedule()
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), schedule.activeDays)
    }

    @Test
    fun testFromJsonAndFromMapFallbackToDefaultWhenMissingOrEmpty() {
        // Missing activeDays in JSON
        val jsonMissing = "{\"isEnabled\":true,\"bedtimeHour\":20,\"bedtimeMinute\":30}"
        val scheduleMissing = BedtimeSchedule.fromJson(jsonMissing)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), scheduleMissing.activeDays)

        // Empty activeDays in JSON
        val jsonEmpty = "{\"isEnabled\":true,\"activeDays\":[]}"
        val scheduleEmpty = BedtimeSchedule.fromJson(jsonEmpty)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), scheduleEmpty.activeDays)

        // Missing activeDays in Map
        val mapMissing = mapOf<String, Any>("isEnabled" to true)
        val scheduleMapMissing = BedtimeSchedule.fromMap(mapMissing)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), scheduleMapMissing.activeDays)

        // Empty activeDays in Map
        val mapEmpty = mapOf<String, Any>("isEnabled" to true, "activeDays" to emptyList<Int>())
        val scheduleMapEmpty = BedtimeSchedule.fromMap(mapEmpty)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), scheduleMapEmpty.activeDays)
    }

    @Test
    fun testSchoolDaysJsonAndMapSerialization() {
        val schoolDays = listOf(1, 2, 3, 4, 5)
        val original = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = schoolDays
        )

        // Map roundtrip
        val map = original.toMap()
        assertEquals(schoolDays, map["activeDays"])
        val fromMap = BedtimeSchedule.fromMap(map)
        assertEquals(schoolDays, fromMap.activeDays)

        // JSON roundtrip
        val json = original.toJson()
        val fromJson = BedtimeSchedule.fromJson(json)
        assertEquals(schoolDays, fromJson.activeDays)
        assertEquals(original, fromJson)
    }

    @Test
    fun testSchoolDaysIsBedtimeActiveAcrossFullWeek() {
        // School days schedule: active Monday to Friday (1..5)
        // Bedtime 20:30 to 06:45
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5)
        )

        // Reference week:
        // 2026-10-19: Monday
        // 2026-10-20: Tuesday
        // 2026-10-21: Wednesday
        // 2026-10-22: Thursday
        // 2026-10-23: Friday
        // 2026-10-24: Saturday
        // 2026-10-25: Sunday
        // 2026-10-26: Monday

        // --- MONDAY (Oct 19) ---
        assertFalse("Monday noon should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 19, 12, 0).timeInMillis))
        assertTrue("Monday 20:30 bedtime start should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 19, 20, 30).timeInMillis))
        assertTrue("Monday night 22:00 should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 19, 22, 0).timeInMillis))
        assertTrue("Monday night 23:59 should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 19, 23, 59).timeInMillis))

        // --- TUESDAY (Oct 20) ---
        assertTrue("Tuesday 01:00 (from Monday night) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 20, 1, 0).timeInMillis))
        assertTrue("Tuesday 06:44 (before wakeup) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 20, 6, 44).timeInMillis))
        assertFalse("Tuesday 06:45 (wakeup time) should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 20, 6, 45).timeInMillis))
        assertFalse("Tuesday noon should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 20, 12, 0).timeInMillis))
        assertTrue("Tuesday 20:30 bedtime start should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 20, 20, 30).timeInMillis))
        assertTrue("Tuesday night 23:00 should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 20, 23, 0).timeInMillis))

        // --- WEDNESDAY (Oct 21) ---
        assertTrue("Wednesday 03:00 (from Tuesday night) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 21, 3, 0).timeInMillis))
        assertFalse("Wednesday 07:00 (after wakeup) should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 21, 7, 0).timeInMillis))
        assertFalse("Wednesday noon should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 21, 12, 0).timeInMillis))
        assertTrue("Wednesday 20:30 bedtime start should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 21, 20, 30).timeInMillis))

        // --- THURSDAY (Oct 22) ---
        assertTrue("Thursday 04:00 (from Wednesday night) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 22, 4, 0).timeInMillis))
        assertFalse("Thursday noon should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 22, 12, 0).timeInMillis))
        assertTrue("Thursday 20:30 bedtime start should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 22, 20, 30).timeInMillis))

        // --- FRIDAY (Oct 23) ---
        assertTrue("Friday 05:00 (from Thursday night) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 23, 5, 0).timeInMillis))
        assertFalse("Friday 06:45 should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 23, 6, 45).timeInMillis))
        assertFalse("Friday noon should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 23, 12, 0).timeInMillis))
        assertTrue("Friday 20:30 bedtime start should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 23, 20, 30).timeInMillis))
        assertTrue("Friday night 23:30 should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 23, 23, 30).timeInMillis))

        // --- SATURDAY (Oct 24) ---
        assertTrue("Saturday 03:00 (from Friday night) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 24, 3, 0).timeInMillis))
        assertTrue("Saturday 06:44 (before wakeup from Friday night) should be active",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 24, 6, 44).timeInMillis))
        assertFalse("Saturday 06:45 should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 24, 6, 45).timeInMillis))
        assertFalse("Saturday noon should be inactive",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 24, 12, 0).timeInMillis))
        assertFalse("Saturday 20:30 night should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 24, 20, 30).timeInMillis))
        assertFalse("Saturday 23:00 night should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 24, 23, 0).timeInMillis))

        // --- SUNDAY (Oct 25) ---
        assertFalse("Sunday 03:00 morning should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 25, 3, 0).timeInMillis))
        assertFalse("Sunday 06:44 should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 25, 6, 44).timeInMillis))
        assertFalse("Sunday noon should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 25, 12, 0).timeInMillis))
        assertFalse("Sunday 20:30 night should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 25, 20, 30).timeInMillis))
        assertFalse("Sunday 23:00 night should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 25, 23, 0).timeInMillis))

        // --- FOLLOWING MONDAY (Oct 26) ---
        assertFalse("Monday 03:00 early morning should be INACTIVE (Sunday night was off)",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 26, 3, 0).timeInMillis))
        assertFalse("Monday 06:44 morning should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 26, 6, 44).timeInMillis))
        assertFalse("Monday noon should be INACTIVE",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 26, 12, 0).timeInMillis))
        assertTrue("Monday 20:30 night should be ACTIVE again",
            schedule.isBedtimeActive(createCal(2026, Calendar.OCTOBER, 26, 20, 30).timeInMillis))
    }

    @Test
    fun testGetNextBedtimeMillis_FridayNightJumpsToMonday() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5)
        )

        // Friday Oct 23 at 21:00 (past Friday's bedtime trigger)
        val fridayNight = createCal(2026, Calendar.OCTOBER, 23, 21, 0)
        val nextBedtimeFromFridayNight = schedule.getNextBedtimeMillis(fridayNight.timeInMillis)
        val expectedMondayBedtime = createCal(2026, Calendar.OCTOBER, 26, 20, 30)
        assertEquals("Next bedtime from Friday night must jump over weekend to Monday 20:30",
            expectedMondayBedtime.timeInMillis, nextBedtimeFromFridayNight)

        // Saturday Oct 24 at 10:00 AM
        val saturdayMorning = createCal(2026, Calendar.OCTOBER, 24, 10, 0)
        val nextBedtimeFromSaturday = schedule.getNextBedtimeMillis(saturdayMorning.timeInMillis)
        assertEquals("Next bedtime from Saturday must be Monday 20:30",
            expectedMondayBedtime.timeInMillis, nextBedtimeFromSaturday)

        // Sunday Oct 25 at 14:00 PM
        val sundayAfternoon = createCal(2026, Calendar.OCTOBER, 25, 14, 0)
        val nextBedtimeFromSunday = schedule.getNextBedtimeMillis(sundayAfternoon.timeInMillis)
        assertEquals("Next bedtime from Sunday must be Monday 20:30",
            expectedMondayBedtime.timeInMillis, nextBedtimeFromSunday)
    }

    @Test
    fun testGetNextWakeupMillis_FridayNightAndWeekend() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5)
        )

        // Friday Oct 23 at 22:00 (during Friday bedtime)
        val fridayNight = createCal(2026, Calendar.OCTOBER, 23, 22, 0)
        val nextWakeupFromFridayNight = schedule.getNextWakeupMillis(fridayNight.timeInMillis)
        val expectedSaturdayWakeup = createCal(2026, Calendar.OCTOBER, 24, 6, 45)
        assertEquals("Next wakeup from Friday night must be Saturday 06:45",
            expectedSaturdayWakeup.timeInMillis, nextWakeupFromFridayNight)

        // Saturday Oct 24 at 02:00 AM (during Friday night's overnight bedtime)
        val saturdayEarlyMorning = createCal(2026, Calendar.OCTOBER, 24, 2, 0)
        val nextWakeupFromSatMorning = schedule.getNextWakeupMillis(saturdayEarlyMorning.timeInMillis)
        assertEquals("Next wakeup from Saturday 02:00 AM must be Saturday 06:45",
            expectedSaturdayWakeup.timeInMillis, nextWakeupFromSatMorning)

        // Saturday Oct 24 at 07:00 AM (after Saturday wakeup)
        // Next bedtime is Monday night Oct 26 -> next wakeup is Tuesday morning Oct 27 at 06:45
        val saturdayAfterWakeup = createCal(2026, Calendar.OCTOBER, 24, 7, 0)
        val nextWakeupFromSatDay = schedule.getNextWakeupMillis(saturdayAfterWakeup.timeInMillis)
        val expectedTuesdayWakeup = createCal(2026, Calendar.OCTOBER, 27, 6, 45)
        assertEquals("Next wakeup after Saturday wakeup must be Tuesday morning 06:45",
            expectedTuesdayWakeup.timeInMillis, nextWakeupFromSatDay)

        // Sunday Oct 25 at 12:00 noon
        val sundayNoon = createCal(2026, Calendar.OCTOBER, 25, 12, 0)
        val nextWakeupFromSunday = schedule.getNextWakeupMillis(sundayNoon.timeInMillis)
        assertEquals("Next wakeup from Sunday noon must be Tuesday morning 06:45",
            expectedTuesdayWakeup.timeInMillis, nextWakeupFromSunday)
    }
}
