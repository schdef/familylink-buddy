package com.familylink.buddy.child

import com.familylink.buddy.child.service.LocalHttpServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalHttpServerLogicTest {

    @Test
    fun testPortConstant() {
        assertEquals(8085, LocalHttpServer.PORT)
    }

    @Test
    fun testStopServerClearsInstance() {
        LocalHttpServer.stopServer()
        assertNull(LocalHttpServer.getInstance())
    }
}
