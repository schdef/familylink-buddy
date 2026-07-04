package com.familylink.buddy.child

import com.familylink.buddy.child.data.AppUsage
import com.familylink.buddy.child.data.FamilyTimeData
import com.familylink.buddy.child.data.FamilyTimeRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FamilyTimeDataTest {

    @Test
    fun testSerializationDeserialization() {
        val usages = listOf(
            AppUsage("com.google.android.youtube", "YouTube", 15, 30),
            AppUsage("com.mojang.minecraftpe", "Minecraft", 20, 60)
        )
        val serialized = FamilyTimeRepository.serializeAppUsages(usages)
        val deserialized = FamilyTimeRepository.deserializeAppUsages(serialized)

        assertEquals(2, deserialized.size)
        assertEquals("com.google.android.youtube", deserialized[0].packageName)
        assertEquals("YouTube", deserialized[0].appName)
        assertEquals(15, deserialized[0].usedMinutes)
        assertEquals(30, deserialized[0].limitMinutes)
        assertEquals(15, deserialized[0].remainingMinutes)

        assertEquals("com.mojang.minecraftpe", deserialized[1].packageName)
        assertEquals(40, deserialized[1].remainingMinutes)
    }

    @Test
    fun testPreserveNonSystemAppLimits() {
        // Mock currentData in DataStore containing Minecraft limit
        val currentAppUsages = listOf(
            AppUsage("com.google.android.youtube", "YouTube", 15, 30),
            AppUsage("com.mojang.minecraftpe", "Minecraft", 20, 60)
        )

        // Mock new app list query (Minecraft is not installed, so it is missing from launcher apps list)
        val updatedAppUsages = listOf(
            AppUsage("com.google.android.youtube", "YouTube", 10, 30) // youtube is installed, minecraft is not
        )

        // Run the preservation logic
        val updatedPackageNames = updatedAppUsages.map { it.packageName }.toSet()
        val preservedUsages = currentAppUsages.filter {
            it.packageName !in updatedPackageNames && it.limitMinutes < 1440
        }
        val finalAppUsages = updatedAppUsages + preservedUsages

        // Verify that Minecraft is preserved and not deleted
        assertEquals(2, finalAppUsages.size)
        
        val youtube = finalAppUsages.first { it.packageName == "com.google.android.youtube" }
        assertEquals(10, youtube.usedMinutes) // updated usage
        assertEquals(30, youtube.limitMinutes)

        val minecraft = finalAppUsages.first { it.packageName == "com.mojang.minecraftpe" }
        assertEquals(20, minecraft.usedMinutes) // preserved usage
        assertEquals(60, minecraft.limitMinutes) // preserved limit!
    }
}
