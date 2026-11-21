package com.familylink.buddy.child

import com.familylink.buddy.child.data.AccessibilityAutoRecovery
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccessibilityAutoRecoveryLogicTest {

    private val testPackage = "com.familylink.buddy.child"
    private val testServiceClass = "com.familylink.buddy.child.service.WifiAccessibilityHelperService"
    private val expectedService = "$testPackage/$testServiceClass"

    @Test
    fun testBuildUpdatedServicesWhenNullOrEmpty() {
        val resultNull = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = null,
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals(expectedService, resultNull)

        val resultEmpty = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = "",
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals(expectedService, resultEmpty)

        val resultBlank = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = "   ",
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals(expectedService, resultBlank)
    }

    @Test
    fun testBuildUpdatedServicesWhenAlreadyPresent() {
        val current = expectedService
        val result = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = current,
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals(expectedService, result)

        val multipleWithTarget = "com.google.android.talkback/.TalkBackService:$expectedService"
        val resultMultiple = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = multipleWithTarget,
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals(multipleWithTarget, resultMultiple)
    }

    @Test
    fun testBuildUpdatedServicesWhenOtherServicesPresent() {
        val otherService = "com.google.android.marvin.talkback/.TalkBackService"
        val result = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = otherService,
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals("$otherService:$expectedService", result)
    }

    @Test
    fun testBuildUpdatedServicesHandlesWhitespaceAndColonsCleanly() {
        val messy = "  com.foo/.Service1 :  com.bar/.Service2  "
        val result = AccessibilityAutoRecovery.buildUpdatedAccessibilityServices(
            currentServices = messy,
            packageName = testPackage,
            serviceClassName = testServiceClass
        )
        assertEquals("com.foo/.Service1:com.bar/.Service2:$expectedService", result)
    }
}
