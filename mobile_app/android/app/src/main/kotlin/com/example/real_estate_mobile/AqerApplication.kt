package com.example.real_estate_mobile

import android.app.Application
import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging

class AqerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initializes the same native SDK after a cold process start too.
        // Manifest auto-init remains false: initialization is not opt-in and
        // does not itself request an FCM registration token.
        if (PushFirebase.configured()) PushFirebase.initialize(this)
    }
}

object PushFirebase {
    fun configured(): Boolean = BuildConfig.AQER_PUSH_ENABLED &&
        BuildConfig.AQER_FIREBASE_API_KEY.isNotBlank() && BuildConfig.AQER_FIREBASE_APP_ID.isNotBlank() &&
        BuildConfig.AQER_FIREBASE_PROJECT_ID.isNotBlank() && BuildConfig.AQER_FIREBASE_SENDER_ID.isNotBlank()

    @Synchronized fun initialize(context: Context) {
        check(configured())
        if (FirebaseApp.getApps(context).isEmpty()) {
            val options = FirebaseOptions.Builder().setApiKey(BuildConfig.AQER_FIREBASE_API_KEY)
                .setApplicationId(BuildConfig.AQER_FIREBASE_APP_ID).setProjectId(BuildConfig.AQER_FIREBASE_PROJECT_ID)
                .setGcmSenderId(BuildConfig.AQER_FIREBASE_SENDER_ID).build()
            checkNotNull(FirebaseApp.initializeApp(context, options))
        }
        FirebaseMessaging.getInstance().isAutoInitEnabled = false
    }
}
