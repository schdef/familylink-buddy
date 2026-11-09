package com.familylink.buddy.child.service

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.familylink.buddy.child.BuildConfig

class NsdHelper(
    private val context: Context,
    private val deviceId: String,
    private val version: String = BuildConfig.VERSION_NAME
) {
    companion object {
        private const val TAG = "NsdHelper"
        const val SERVICE_TYPE = "_familylinkbuddy._tcp"
        const val PORT = 8085
    }

    private val nsdManager: NsdManager? by lazy {
        context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    }

    private var registrationListener: NsdManager.RegistrationListener? = null
    private var registeredServiceName: String? = null

    @Synchronized
    fun registerService() {
        if (registrationListener != null) {
            Log.w(TAG, "Service is already registered or registration is pending")
            return
        }

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "FamilyLinkBuddy-$deviceId"
            serviceType = SERVICE_TYPE
            port = PORT
            setAttribute("deviceId", deviceId)
            setAttribute("version", version)
        }

        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                registeredServiceName = serviceInfo.serviceName
                Log.i(TAG, "NSD service successfully registered: ${serviceInfo.serviceName} on port ${serviceInfo.port}")
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD service registration failed for ${serviceInfo.serviceName}: errorCode=$errorCode")
                synchronized(this@NsdHelper) {
                    registrationListener = null
                }
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                Log.i(TAG, "NSD service successfully unregistered: ${serviceInfo.serviceName}")
                synchronized(this@NsdHelper) {
                    registrationListener = null
                    registeredServiceName = null
                }
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD service unregistration failed for ${serviceInfo.serviceName}: errorCode=$errorCode")
                synchronized(this@NsdHelper) {
                    registrationListener = null
                }
            }
        }

        registrationListener = listener

        try {
            nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
            Log.d(TAG, "Initiated NSD service registration: FamilyLinkBuddy-$deviceId type=$SERVICE_TYPE port=$PORT")
        } catch (e: Exception) {
            Log.e(TAG, "Exception during registerService", e)
            registrationListener = null
        }
    }

    @Synchronized
    fun unregisterService() {
        val listener = registrationListener ?: return
        try {
            nsdManager?.unregisterService(listener)
            Log.d(TAG, "Initiated NSD service unregistration")
        } catch (e: Exception) {
            Log.e(TAG, "Exception during unregisterService", e)
        } finally {
            registrationListener = null
            registeredServiceName = null
        }
    }
}
