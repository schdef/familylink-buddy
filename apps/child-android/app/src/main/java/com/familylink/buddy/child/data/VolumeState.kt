package com.familylink.buddy.child.data

data class VolumeState(
    val mediaVolume: Int = -1,       // 0–15, -1 = unknown
    val ringtoneVolume: Int = -1,
    val alarmVolume: Int = -1,
    val maxMediaVolume: Int = 15,
    val maxRingtoneVolume: Int = 15,
    val maxAlarmVolume: Int = 15,
    val isMuted: Boolean = false,
    val deviceToken: String = ""     // FCM token for this device (shown for pairing)
)
