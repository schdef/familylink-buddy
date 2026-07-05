package com.familylink.buddy.child

import android.app.Application
import android.util.Log
import com.google.firebase.Firebase
import com.google.firebase.firestore.firestore
import com.google.firebase.functions.functions

class FamilyLinkBuddyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            if (BuildConfig.USE_EMULATOR) {
                Firebase.firestore.useEmulator("10.0.2.2", 8080)
                Firebase.functions.useEmulator("10.0.2.2", 5001)
                Log.d("FamilyLinkBuddyApp", "Firebase clients redirected to local emulators (10.0.2.2)")
            }
        } catch (e: Exception) {
            Log.e("FamilyLinkBuddyApp", "Failed to configure Firebase emulators", e)
        }
    }
}
