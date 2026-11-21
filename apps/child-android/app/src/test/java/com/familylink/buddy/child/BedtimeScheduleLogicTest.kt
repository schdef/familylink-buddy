package com.familylink.buddy.child

import android.content.Intent
import com.familylink.buddy.child.data.BedtimeSchedule
import com.familylink.buddy.child.service.BedtimeScheduleReceiver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class BedtimeScheduleLogicTest {

    @Test
    fun testDefaultValues() {
        val schedule = BedtimeSchedule()
        assertFalse(schedule.isEnabled)
        assertEquals(20, schedule.bedtimeHour)
        assertEquals(30, schedule.bedtimeMinute)
        assertEquals(6, schedule.wakeupHour)
        assertEquals(45, schedule.wakeupMinute)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), schedule.activeDays)
        assertFalse(schedule.isCurrentlyBlocked)
        assertTrue(schedule.isOvernight)
    }

    @Test
    fun testMapSerializationRoundtrip() {
        val original = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 21,
            bedtimeMinute = 15,
            wakeupHour = 7,
            wakeupMinute = 0,
            activeDays = listOf(1, 2, 3, 4, 5),
            isCurrentlyBlocked = true
        )

        val map = original.toMap()
        assertEquals(true, map["isEnabled"])
        assertEquals(21, map["bedtimeHour"])
        assertEquals(15, map["bedtimeMinute"])
        assertEquals(7, map["wakeupHour"])
        assertEquals(0, map["wakeupMinute"])
        assertEquals(listOf(1, 2, 3, 4, 5), map["activeDays"])
        assertEquals(true, map["isCurrentlyBlocked"])

        val deserialized = BedtimeSchedule.fromMap(map)
        assertEquals(original, deserialized)
    }

    @Test
    fun testJsonSerializationRoundtrip() {
        val original = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 22,
            bedtimeMinute = 0,
            wakeupHour = 8,
            wakeupMinute = 30,
            activeDays = listOf(6, 7),
            isCurrentlyBlocked = false
        )

        val json = original.toJson()
        val deserialized = BedtimeSchedule.fromJson(json)
        assertEquals(original, deserialized)
    }

    @Test
    fun testCalendarDayToIsoConversion() {
        assertEquals(7, BedtimeSchedule.calendarDayToIso(Calendar.SUNDAY))
        assertEquals(1, BedtimeSchedule.calendarDayToIso(Calendar.MONDAY))
        assertEquals(2, BedtimeSchedule.calendarDayToIso(Calendar.TUESDAY))
        assertEquals(3, BedtimeSchedule.calendarDayToIso(Calendar.WEDNESDAY))
        assertEquals(4, BedtimeSchedule.calendarDayToIso(Calendar.THURSDAY))
        assertEquals(5, BedtimeSchedule.calendarDayToIso(Calendar.FRIDAY))
        assertEquals(6, BedtimeSchedule.calendarDayToIso(Calendar.SATURDAY))

        assertEquals(Calendar.SUNDAY, BedtimeSchedule.isoToCalendarDay(7))
        assertEquals(Calendar.MONDAY, BedtimeSchedule.isoToCalendarDay(1))
        assertEquals(Calendar.SATURDAY, BedtimeSchedule.isoToCalendarDay(6))
    }

    @Test
    fun testNextBedtimeMillis_SameDayUpcoming() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5, 6, 7)
        )

        // Fixed point: Monday 14:00:00.000
        val mondayCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, 2026)
            set(Calendar.MONTH, Calendar.OCTOBER)
            set(Calendar.DAY_OF_MONTH, 19) // Monday Oct 19, 2026
            set(Calendar.HOUR_OF_DAY, 14)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val fromMillis = mondayCal.timeInMillis

        val nextBedtimeMillis = schedule.getNextBedtimeMillis(fromMillis)

        val expectedCal = (mondayCal.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 20)
            set(Calendar.MINUTE, 30)
        }
        assertEquals(expectedCal.timeInMillis, nextBedtimeMillis)
    }

    @Test
    fun testNextBedtimeMillis_DayRollover() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5, 6, 7)
        )

        // Monday 21:00 (past Monday bedtime)
        val mondayCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, 2026)
            set(Calendar.MONTH, Calendar.OCTOBER)
            set(Calendar.DAY_OF_MONTH, 19) // Monday
            set(Calendar.HOUR_OF_DAY, 21)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val nextBedtimeMillis = schedule.getNextBedtimeMillis(mondayCal.timeInMillis)

        // Expected: Tuesday Oct 20 at 20:30
        val expectedCal = (mondayCal.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, 1) // Tuesday
            set(Calendar.HOUR_OF_DAY, 20)
            set(Calendar.MINUTE, 30)
        }
        assertEquals(expectedCal.timeInMillis, nextBedtimeMillis)
    }

    @Test
    fun testNextBedtimeMillis_SkipInactiveDays() {
        // Only active on Friday (5)
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(5)
        )

        // Monday Oct 19 at 10:00
        val mondayCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, 2026)
            set(Calendar.MONTH, Calendar.OCTOBER)
            set(Calendar.DAY_OF_MONTH, 19) // Monday (1)
            set(Calendar.HOUR_OF_DAY, 10)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val nextBedtimeMillis = schedule.getNextBedtimeMillis(mondayCal.timeInMillis)

        // Expected: Friday Oct 23 at 20:30
        val expectedCal = (mondayCal.clone() as Calendar).apply {
            set(Calendar.DAY_OF_MONTH, 23) // Friday (5)
            set(Calendar.HOUR_OF_DAY, 20)
            set(Calendar.MINUTE, 30)
        }
        assertEquals(expectedCal.timeInMillis, nextBedtimeMillis)
    }

    @Test
    fun testWakeupAndBedtimeStatus_DuringOvernightBedtime() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5, 6, 7)
        )

        // Monday Oct 19 at 22:30 (during bedtime)
        val mondayNightCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, 2026)
            set(Calendar.MONTH, Calendar.OCTOBER)
            set(Calendar.DAY_OF_MONTH, 19)
            set(Calendar.HOUR_OF_DAY, 22)
            set(Calendar.MINUTE, 30)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertTrue(schedule.isBedtimeActive(mondayNightCal.timeInMillis))

        // Next wakeup should be Tuesday morning 06:45
        val nextWakeupMillis = schedule.getNextWakeupMillis(mondayNightCal.timeInMillis)
        val expectedWakeupCal = (mondayNightCal.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, 1) // Tuesday
            set(Calendar.HOUR_OF_DAY, 6)
            set(Calendar.MINUTE, 45)
        }
        assertEquals(expectedWakeupCal.timeInMillis, nextWakeupMillis)
    }

    @Test
    fun testWakeupAndBedtimeStatus_EarlyMorningBeforeWakeup() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5, 6, 7)
        )

        // Tuesday Oct 20 at 05:00 (started Monday night, still before 06:45)
        val tuesdayMorningCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, 2026)
            set(Calendar.MONTH, Calendar.OCTOBER)
            set(Calendar.DAY_OF_MONTH, 20)
            set(Calendar.HOUR_OF_DAY, 5)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertTrue(schedule.isBedtimeActive(tuesdayMorningCal.timeInMillis))

        val nextWakeupMillis = schedule.getNextWakeupMillis(tuesdayMorningCal.timeInMillis)
        val expectedWakeupCal = (tuesdayMorningCal.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 6)
            set(Calendar.MINUTE, 45)
        }
        assertEquals(expectedWakeupCal.timeInMillis, nextWakeupMillis)
    }

    @Test
    fun testWakeupAndBedtimeStatus_DaytimeOutsideBedtime() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45,
            activeDays = listOf(1, 2, 3, 4, 5, 6, 7)
        )

        // Tuesday Oct 20 at 12:00
        val tuesdayNoonCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, 2026)
            set(Calendar.MONTH, Calendar.OCTOBER)
            set(Calendar.DAY_OF_MONTH, 20)
            set(Calendar.HOUR_OF_DAY, 12)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertFalse(schedule.isBedtimeActive(tuesdayNoonCal.timeInMillis))

        // Next wakeup follows Tuesday night's bedtime -> Wednesday morning 06:45
        val nextWakeupMillis = schedule.getNextWakeupMillis(tuesdayNoonCal.timeInMillis)
        val expectedWakeupCal = (tuesdayNoonCal.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, 1) // Wednesday
            set(Calendar.HOUR_OF_DAY, 6)
            set(Calendar.MINUTE, 45)
        }
        assertEquals(expectedWakeupCal.timeInMillis, nextWakeupMillis)
    }

    @Test
    fun testDisabledScheduleReturnsInactive() {
        val schedule = BedtimeSchedule(
            isEnabled = false,
            bedtimeHour = 20,
            bedtimeMinute = 30,
            wakeupHour = 6,
            wakeupMinute = 45
        )

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 23)
            set(Calendar.MINUTE, 0)
        }

        assertFalse(schedule.isBedtimeActive(cal.timeInMillis))
    }

    @Test
    fun testEmptyActiveDaysReturnsMinusOne() {
        val schedule = BedtimeSchedule(
            isEnabled = true,
            activeDays = emptyList()
        )

        val now = System.currentTimeMillis()
        assertEquals(-1L, schedule.getNextBedtimeMillis(now))
        assertEquals(-1L, schedule.getNextWakeupMillis(now))
        assertFalse(schedule.isBedtimeActive(now))
    }

    @Test
    fun testBedtimeScheduleReceiverRescheduleActions() {
        assertEquals("android.intent.action.MY_PACKAGE_REPLACED", BedtimeScheduleReceiver.ACTION_MY_PACKAGE_REPLACED)
        assertTrue(BedtimeScheduleReceiver.isRescheduleAction(Intent.ACTION_BOOT_COMPLETED))
        assertTrue(BedtimeScheduleReceiver.isRescheduleAction(Intent.ACTION_MY_PACKAGE_REPLACED))
        assertTrue(BedtimeScheduleReceiver.isRescheduleAction(BedtimeScheduleReceiver.ACTION_MY_PACKAGE_REPLACED))
        assertTrue(BedtimeScheduleReceiver.isRescheduleAction(BedtimeScheduleReceiver.ACTION_QUICKBOOT_POWERON))

        assertFalse(BedtimeScheduleReceiver.isRescheduleAction(BedtimeScheduleReceiver.ACTION_TRIGGER_BEDTIME))
        assertFalse(BedtimeScheduleReceiver.isRescheduleAction(BedtimeScheduleReceiver.ACTION_TRIGGER_WAKEUP))
        assertFalse(BedtimeScheduleReceiver.isRescheduleAction(null))
        assertFalse(BedtimeScheduleReceiver.isRescheduleAction("android.intent.action.SOME_OTHER_ACTION"))
    }
}
