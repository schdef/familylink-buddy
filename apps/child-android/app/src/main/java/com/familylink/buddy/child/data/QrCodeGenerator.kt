package com.familylink.buddy.child.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

object QrCodeGenerator {
    fun generateQrCode(text: String, size: Int = 512): Bitmap? {
        return try {
            val writer = QRCodeWriter()
            val bitMatrix = writer.encode(text, BarcodeFormat.QR_CODE, size, size)
            val width = bitMatrix.width
            val height = bitMatrix.height
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
            for (x in 0 until width) {
                for (y in 0 until height) {
                    bitmap.setPixel(x, y, if (bitMatrix.get(x, y)) Color.BLACK else Color.WHITE)
                }
            }
            bitmap
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun createPairingPayload(
        deviceId: String,
        deviceName: String,
        ip: String,
        port: Int = 8085,
        token: String
    ): String {
        return JSONObject().apply {
            put("v", 1)
            put("deviceId", deviceId)
            put("deviceName", deviceName)
            put("ip", ip)
            put("port", port)
            put("token", token)
        }.toString()
    }

    fun getLocalIpAddress(context: Context? = null): String {
        try {
            val wifiManager = context?.applicationContext?.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            val ipInt = wifiManager?.connectionInfo?.ipAddress ?: 0
            if (ipInt != 0) {
                val ip = String.format(
                    java.util.Locale.US,
                    "%d.%d.%d.%d",
                    ipInt and 0xff,
                    ipInt shr 8 and 0xff,
                    ipInt shr 16 and 0xff,
                    ipInt shr 24 and 0xff
                )
                if (ip != "0.0.0.0" && ip != "127.0.0.1") return ip
            }
        } catch (_: Exception) {
        }

        try {
            val networkInterfaces = NetworkInterface.getNetworkInterfaces()
            val interfaces = if (networkInterfaces != null) {
                Collections.list(networkInterfaces)
                    .filter { iface ->
                        try {
                            iface.isUp && !iface.isLoopback
                        } catch (_: Exception) {
                            false
                        }
                    }
                    .filterNot { iface ->
                        val name = iface.name.lowercase()
                        name.startsWith("p2p") || name.startsWith("dummy") || name.startsWith("tun")
                    }
                    .sortedWith(Comparator { iface1, iface2 ->
                        val name1 = iface1.name.lowercase()
                        val name2 = iface2.name.lowercase()
                        val p1 = if (name1.startsWith("wlan") || name1.startsWith("eth")) 0 else 1
                        val p2 = if (name2.startsWith("wlan") || name2.startsWith("eth")) 0 else 1
                        p1.compareTo(p2)
                    })
            } else {
                emptyList()
            }

            var fallbackNonLoopback: String? = null

            for (iface in interfaces) {
                val addresses = iface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (!address.isLoopbackAddress && address is Inet4Address) {
                        val ip = address.hostAddress ?: continue
                        if (ip.startsWith("192.168.") || ip.startsWith("10.") || ip.startsWith("172.")) {
                            return ip
                        }
                        if (fallbackNonLoopback == null && ip != "0.0.0.0" && ip != "127.0.0.1") {
                            fallbackNonLoopback = ip
                        }
                    }
                }
            }

            if (fallbackNonLoopback != null) {
                return fallbackNonLoopback
            }
        } catch (_: Exception) {
        }
        return "127.0.0.1"
    }

    fun getDeviceName(context: Context): String {
        return try {
            Settings.Global.getString(context.contentResolver, "device_name")
                ?: Settings.Secure.getString(context.contentResolver, "bluetooth_name")
                ?: Build.MODEL
        } catch (_: Exception) {
            Build.MODEL
        } ?: "Child Tablet"
    }
}
