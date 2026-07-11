package com.familylink.buddy.child.data

data class FamilyTimeData(
    val totalRemainingMinutes: Int = 60,
    val totalLimitMinutes: Int = 120,
    val lastUpdatedMillis: Long = System.currentTimeMillis(),
    val appUsages: List<AppUsage> = emptyList()
) {
    val safeRemainingMinutes: Int get() = totalRemainingMinutes.coerceAtLeast(0)
}

data class AppUsage(
    val packageName: String,
    val appName: String,
    val usedMinutes: Int,
    val limitMinutes: Int
) {
    val remainingMinutes: Int
        get() = (limitMinutes - usedMinutes).coerceAtLeast(0)
}
