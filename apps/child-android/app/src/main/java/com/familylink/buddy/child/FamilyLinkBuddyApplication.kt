package com.familylink.buddy.child

import android.app.Application
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.service.LocalHttpServer

class FamilyLinkBuddyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        LocalHttpServer.startServer(this, FamilyTimeRepository(this))
    }
}
