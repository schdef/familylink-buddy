package com.familylink.buddy.child

import com.familylink.buddy.child.data.TimeBankState
import com.familylink.buddy.child.data.BonusTask
import com.familylink.buddy.child.data.RewardItem
import com.familylink.buddy.child.data.RewardClaim
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

class TimeBankDataTest {

    @Test
    fun testTimeBankStateDefaults() {
        val state = TimeBankState()
        assertFalse(state.isEnabled)
        assertFalse(state.isChildVisible)
        assertEquals(0, state.balance)
    }

    @Test
    fun testBonusTaskConstruction() {
        val task = BonusTask(
            id = "task-123",
            title = "Zimmer aufräumen",
            emoji = "🧹",
            reward = 15,
            hasDuration = true,
            durationMinutes = 20,
            status = "IN_PROGRESS"
        )
        assertEquals("task-123", task.id)
        assertEquals("Zimmer aufräumen", task.title)
        assertEquals("🧹", task.emoji)
        assertEquals(15, task.reward)
        assertTrue(task.hasDuration)
        assertEquals(20, task.durationMinutes)
        assertEquals("IN_PROGRESS", task.status)
    }

    @Test
    fun testRewardItemConstruction() {
        val reward = RewardItem(
            id = "reward-1",
            title = "1 Std. Minecraft",
            emoji = "🎮",
            cost = 50
        )
        assertEquals("reward-1", reward.id)
        assertEquals("1 Std. Minecraft", reward.title)
        assertEquals("🎮", reward.emoji)
        assertEquals(50, reward.cost)
    }

    @Test
    fun testRewardClaimConstruction() {
        val claim = RewardClaim(
            id = "claim-5",
            rewardId = "reward-1",
            title = "1 Std. Minecraft",
            emoji = "🎮",
            cost = 50,
            status = "PENDING",
            claimedAt = 1680000000L
        )
        assertEquals("claim-5", claim.id)
        assertEquals("reward-1", claim.rewardId)
        assertEquals("1 Std. Minecraft", claim.title)
        assertEquals("🎮", claim.emoji)
        assertEquals(50, claim.cost)
        assertEquals("PENDING", claim.status)
        assertEquals(1680000000L, claim.claimedAt)
        assertNull(claim.fulfilledAt)
    }

    @Test
    fun testLowCoinsThresholdLogic() {
        val balancesToTest = listOf(0, 1, 3, 5, 6, 10)
        val expectedLowWarning = listOf(false, true, true, true, false, false)

        balancesToTest.forEachIndexed { idx, balance ->
            val isLow = balance in 1..5
            assertEquals(expectedLowWarning[idx], isLow)
        }
    }
}
