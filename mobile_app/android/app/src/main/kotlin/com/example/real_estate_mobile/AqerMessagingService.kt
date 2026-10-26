package com.example.real_estate_mobile

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AqerMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        // No notification payload is accepted. Server data is an untrusted hint,
        // never private display content or authority to read a conversation.
        if (BuildConfig.AQER_PUSH_ENABLED && message.notification == null) PushMessageHandler.display(this, message.data)
    }

    override fun onNewToken(token: String) {
        PushSessionState(this).tokenChanged(token)
        Handler(Looper.getMainLooper()).post { PushBridge.onRegistrationChanged?.invoke() }
    }
}

object PushMessageHandler {
    fun display(context: Context, data: Map<String, String>): Boolean = synchronized(PushSessionState.lock) {
        val state = PushSessionState(context)
        if (!state.allows(data)) return@synchronized false
        state.ensureChannel()
        val id = data.getValue("notification_id")
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            data.forEach { (key, value) -> putExtra("aqer_push_$key", value) }
        }
        val pending = PendingIntent.getActivity(context, id.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, PushSessionState.CHANNEL_ID) else Notification.Builder(context)
        val notification = builder.setSmallIcon(R.drawable.ic_stat_aqer)
            .setContentTitle("عقار").setContentText("لديك إشعار جديد. افتح التطبيق لعرضه.")
            .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(pending).build()
        if (!state.markSeen(id)) return@synchronized false
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(PushSessionState.NOTIFICATION_TAG, id.hashCode(), notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }
}
