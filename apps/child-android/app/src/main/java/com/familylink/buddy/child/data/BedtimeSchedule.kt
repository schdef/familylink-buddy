package com.familylink.buddy.child.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Bedtime schedule model for child device bedtime and Wi-Fi restriction.
 *
 * Active days: ISO-8601 day-of-week where:
 * 1 = Monday
 * 2 = Tuesday
 * 3 = Wednesday
 * 4 = Thursday
 * 5 = Friday
 * 6 = Saturday
 * 7 = Sunday
 *
 * (Note: Calendar.SUNDAY is 1, Calendar.MONDAY is 2. The mapping is converted automatically).
 */
data class BedtimeSchedule(
    val isEnabled: Boolean = false,
    val bedtimeHour: Int = 20,
    val bedtimeMinute: Int = 30,
    val wakeupHour: Int = 6,
    val wakeupMinute: Int = 45,
    val activeDays: List<Int> = listOf(1, 2, 3, 4, 5, 6, 7),
    val isCurrentlyBlocked: Boolean = false
) {
    val isOvernight: Boolean
        get() = (bedtimeHour > wakeupHour) || (bedtimeHour == wakeupHour && bedtimeMinute >= wakeupMinute)

    fun toMap(): Map<String, Any> {
        return mapOf(
            "isEnabled" to isEnabled,
            "bedtimeHour" to bedtimeHour,
            "bedtimeMinute" to bedtimeMinute,
            "wakeupHour" to wakeupHour,
            "wakeupMinute" to wakeupMinute,
            "activeDays" to activeDays,
            "isCurrentlyBlocked" to isCurrentlyBlocked
        )
    }

    fun toJson(): String {
        val obj = JSONObject()
        obj.put("isEnabled", isEnabled)
        obj.put("bedtimeHour", bedtimeHour)
        obj.put("bedtimeMinute", bedtimeMinute)
        obj.put("wakeupHour", wakeupHour)
        obj.put("wakeupMinute", wakeupMinute)
        val daysArray = JSONArray()
        activeDays.forEach { daysArray.put(it) }
        obj.put("activeDays", daysArray)
        obj.put("isCurrentlyBlocked", isCurrentlyBlocked)
        return obj.toString()
    }

    /**
     * Determines whether [fromMillis] falls within an active bedtime window.
     */
    fun isBedtimeActive(fromMillis: Long = System.currentTimeMillis()): Boolean {
        if (!isEnabled || activeDays.isEmpty()) return false

        // Check window started yesterday (if overnight)
        if (isOvernight) {
            val yesterdayCal = Calendar.getInstance().apply {
                timeInMillis = fromMillis
                add(Calendar.DAY_OF_YEAR, -1)
            }
            val yesterdayIsoDay = calendarDayToIso(yesterdayCal.get(Calendar.DAY_OF_WEEK))
            if (activeDays.contains(yesterdayIsoDay)) {
                val start = getBedtimeCalendarForDay(yesterdayCal).timeInMillis
                val end = getWakeupCalendarForDay(yesterdayCal).timeInMillis
                if (fromMillis in start until end) {
                    return true
                }
            }
        }

        // Check window started today
        val todayCal = Calendar.getInstance().apply {
            timeInMillis = fromMillis
        }
        val todayIsoDay = calendarDayToIso(todayCal.get(Calendar.DAY_OF_WEEK))
        if (activeDays.contains(todayIsoDay)) {
            val start = getBedtimeCalendarForDay(todayCal).timeInMillis
            val end = getWakeupCalendarForDay(todayCal).timeInMillis
            if (fromMillis in start until end) {
                return true
            }
        }

        return false
    }

    /**
     * Calculates the next upcoming bedtime trigger timestamp in milliseconds after [fromMillis].
     * Returns -1L if activeDays is empty.
     */
    fun getNextBedtimeMillis(fromMillis: Long = System.currentTimeMillis()): Long {
        if (activeDays.isEmpty()) return -1L

        val cal = Calendar.getInstance().apply {
            timeInMillis = fromMillis
        }

        // Check today and up to 7 days ahead
        for (dayOffset in 0..7) {
            val checkCal = Calendar.getInstance().apply {
                timeInMillis = cal.timeInMillis
                add(Calendar.DAY_OF_YEAR, dayOffset)
            }
            val isoDay = calendarDayToIso(checkCal.get(Calendar.DAY_OF_WEEK))
            if (activeDays.contains(isoDay)) {
                val bedtimeCal = getBedtimeCalendarForDay(checkCal)
                if (bedtimeCal.timeInMillis > fromMillis) {
                    return bedtimeCal.timeInMillis
                }
            }
        }
        return -1L
    }

    /**
     * Calculates the next upcoming wakeup trigger timestamp in milliseconds after [fromMillis].
     * Returns -1L if activeDays is empty.
     */
    fun getNextWakeupMillis(fromMillis: Long = System.currentTimeMillis()): Long {
        if (activeDays.isEmpty()) return -1L

        val cal = Calendar.getInstance().apply {
            timeInMillis = fromMillis
        }

        // 1. Check if yesterday had an overnight bedtime whose wakeup is upcoming
        if (isOvernight) {
            val yesterdayCal = Calendar.getInstance().apply {
                timeInMillis = cal.timeInMillis
                add(Calendar.DAY_OF_YEAR, -1)
            }
            val yesterdayIsoDay = calendarDayToIso(yesterdayCal.get(Calendar.DAY_OF_WEEK))
            if (activeDays.contains(yesterdayIsoDay)) {
                val wakeupCal = getWakeupCalendarForDay(yesterdayCal)
                if (wakeupCal.timeInMillis > fromMillis) {
                    return wakeupCal.timeInMillis
                }
            }
        }

        // 2. Check today and upcoming days
        for (dayOffset in 0..7) {
            val checkCal = Calendar.getInstance().apply {
                timeInMillis = cal.timeInMillis
                add(Calendar.DAY_OF_YEAR, dayOffset)
            }
            val isoDay = calendarDayToIso(checkCal.get(Calendar.DAY_OF_WEEK))
            if (activeDays.contains(isoDay)) {
                val wakeupCal = getWakeupCalendarForDay(checkCal)
                if (wakeupCal.timeInMillis > fromMillis) {
                    return wakeupCal.timeInMillis
                }
            }
        }
        return -1L
    }

    private fun getBedtimeCalendarForDay(dayCal: Calendar): Calendar {
        return (dayCal.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, bedtimeHour)
            set(Calendar.MINUTE, bedtimeMinute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    private fun getWakeupCalendarForDay(bedtimeStartDayCal: Calendar): Calendar {
        return (bedtimeStartDayCal.clone() as Calendar).apply {
            if (isOvernight) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
            set(Calendar.HOUR_OF_DAY, wakeupHour)
            set(Calendar.MINUTE, wakeupMinute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    companion object {
        fun calendarDayToIso(calendarDay: Int): Int {
            return if (calendarDay == Calendar.SUNDAY) 7 else calendarDay - 1
        }

        fun isoToCalendarDay(isoDay: Int): Int {
            return if (isoDay == 7) Calendar.SUNDAY else isoDay + 1
        }

        fun fromMap(map: Map<String, Any?>): BedtimeSchedule {
            val isEnabled = (map["isEnabled"] as? Boolean) ?: false
            val bedtimeHour = (map["bedtimeHour"] as? Number)?.toInt() ?: 20
            val bedtimeMinute = (map["bedtimeMinute"] as? Number)?.toInt() ?: 30
            val wakeupHour = (map["wakeupHour"] as? Number)?.toInt() ?: 6
            val wakeupMinute = (map["wakeupMinute"] as? Number)?.toInt() ?: 45
            val activeDays = (map["activeDays"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
                ?: listOf(1, 2, 3, 4, 5, 6, 7)
            val isCurrentlyBlocked = (map["isCurrentlyBlocked"] as? Boolean) ?: false

            return BedtimeSchedule(
                isEnabled = isEnabled,
                bedtimeHour = bedtimeHour,
                bedtimeMinute = bedtimeMinute,
                wakeupHour = wakeupHour,
                wakeupMinute = wakeupMinute,
                activeDays = activeDays,
                isCurrentlyBlocked = isCurrentlyBlocked
            )
        }

        fun fromJson(jsonStr: String): BedtimeSchedule {
            if (jsonStr.isBlank()) return BedtimeSchedule()
            return try {
                val obj = JSONObject(jsonStr)
                val days = mutableListOf<Int>()
                val daysArr = obj.optJSONArray("activeDays")
                if (daysArr != null) {
                    for (i in 0 until daysArr.length()) {
                        days.add(daysArr.getInt(i))
                    }
                } else {
                    days.addAll(listOf(1, 2, 3, 4, 5, 6, 7))
                }
                BedtimeSchedule(
                    isEnabled = obj.optBoolean("isEnabled", false),
                    bedtimeHour = obj.optInt("bedtimeHour", 20),
                    bedtimeMinute = obj.optInt("bedtimeMinute", 30),
                    wakeupHour = obj.optInt("wakeupHour", 6),
                    wakeupMinute = obj.optInt("wakeupMinute", 45),
                    activeDays = if (days.isNotEmpty()) days else listOf(1, 2, 3, 4, 5, 6, 7),
                    isCurrentlyBlocked = obj.optBoolean("isCurrentlyBlocked", false)
                )
            } catch (e: Exception) {
                BedtimeSchedule()
            }
        }
    }
}
