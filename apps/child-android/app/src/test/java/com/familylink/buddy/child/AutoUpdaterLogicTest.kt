package com.familylink.buddy.child

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoUpdaterLogicTest {

    private fun shouldTriggerUpdate(localCode: Long, remoteCode: Long, downloadUrl: String): Boolean {
        return remoteCode > localCode && downloadUrl.isNotEmpty()
    }

    @Test
    fun testUpdateRequiredWhenRemoteIsNewer() {
        val updateNeeded = shouldTriggerUpdate(
            localCode = 1L,
            remoteCode = 2L,
            downloadUrl = "https://drive.google.com/uc?export=download&id=abc123xyz"
        )
        assertTrue(updateNeeded)
    }

    @Test
    fun testNoUpdateRequiredWhenRemoteIsOlder() {
        val updateNeeded = shouldTriggerUpdate(
            localCode = 3L,
            remoteCode = 2L,
            downloadUrl = "https://drive.google.com/uc?export=download&id=abc123xyz"
        )
        assertFalse(updateNeeded)
    }

    @Test
    fun testNoUpdateRequiredWhenRemoteIsSame() {
        val updateNeeded = shouldTriggerUpdate(
            localCode = 2L,
            remoteCode = 2L,
            downloadUrl = "https://drive.google.com/uc?export=download&id=abc123xyz"
        )
        assertFalse(updateNeeded)
    }

    @Test
    fun testNoUpdateWhenDownloadUrlIsEmpty() {
        val updateNeeded = shouldTriggerUpdate(
            localCode = 1L,
            remoteCode = 2L,
            downloadUrl = ""
        )
        assertFalse(updateNeeded)
    }
}
