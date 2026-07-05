package com.familylink.buddy.child.data

data class TimeBankState(
    val isEnabled: Boolean = false,
    val isChildVisible: Boolean = false,
    val balance: Int = 0
)

data class TimeBankTransaction(
    val id: String = "",
    val timestamp: Long = 0,
    val type: String = "MANUAL_AWARD", // BONUS, USAGE, MANUAL_AWARD, TASK_COMPLETE
    val amount: Int = 0,
    val description: String = "",
    val emoji: String = "⏳",
    val date: String = ""
)

data class BonusTask(
    val id: String = "",
    val title: String = "",
    val emoji: String = "📋",
    val reward: Int = 0,
    val hasDuration: Boolean = false,
    val durationMinutes: Int = 0,
    val requiresApproval: Boolean = false,
    val status: String = "AVAILABLE" // AVAILABLE, IN_PROGRESS, PENDING_APPROVAL, COMPLETED
)

data class RewardItem(
    val id: String = "",
    val title: String = "",
    val emoji: String = "🎁",
    val cost: Int = 0
)

data class RewardClaim(
    val id: String = "",
    val rewardId: String = "",
    val title: String = "",
    val emoji: String = "🎁",
    val cost: Int = 0,
    val status: String = "PENDING", // PENDING, FULFILLED
    val claimedAt: Long = 0,
    val fulfilledAt: Long? = null
)
