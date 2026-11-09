package com.familylink.buddy.child

import com.familylink.buddy.child.data.QrCodeGenerator
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class QrCodeGeneratorTest {

    @Test
    fun testCreatePairingPayload() {
        val payload = QrCodeGenerator.createPairingPayload(
            deviceId = "test-device-123",
            deviceName = "Felix Tablet",
            ip = "192.168.1.55",
            port = 8085,
            token = "secret-token-xyz"
        )

        val json = JSONObject(payload)
        assertEquals(1, json.getInt("v"))
        assertEquals("test-device-123", json.getString("deviceId"))
        assertEquals("Felix Tablet", json.getString("deviceName"))
        assertEquals("192.168.1.55", json.getString("ip"))
        assertEquals(8085, json.getInt("port"))
        assertEquals("secret-token-xyz", json.getString("token"))
    }
}
