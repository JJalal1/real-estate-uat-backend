package com.example.real_estate_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest
import java.util.UUID

/** App-private consent and delivery fence; never persists bearer or FCM tokens. */
class PushSessionState(private val context: Context) {
    data class Fence(val session: String, val generation: String)

    companion object {
        val lock = Any()
        const val CHANNEL_ID = "aqer_general"
        const val NOTIFICATION_TAG = "aqer_push"
        private const val PREFS = "aqer_push"
        fun hash(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        fun allowedRoute(route: String): Boolean = route == "/notifications" ||
            Regex("^/(properties|messages)/[1-9][0-9]{0,18}$").matches(route)
    }

    private val prefs get() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val manager get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun sessionChanged(token: String?) = synchronized(lock) {
        clearConsent()
        check(prefs.edit().putString("active_session", token?.let(::hash)).commit())
    }

    fun capture(suppliedToken: String, actualToken: String?): Fence? = synchronized(lock) {
        if (suppliedToken.isBlank() || actualToken == null || suppliedToken != actualToken) return@synchronized null
        val digest = hash(actualToken)
        // An existing installation can predate this fence. Migrate by revoking
        // its old device-wide consent, never silently enrolling the account.
        if (prefs.getString("active_session", null) != digest) sessionChanged(actualToken)
        Fence(digest, prefs.getString("generation", "").orEmpty())
    }

    fun current(fence: Fence): Boolean = synchronized(lock) {
        fence.session.isNotBlank() && prefs.getString("active_session", null) == fence.session &&
            prefs.getString("generation", null) == fence.generation
    }

    fun optedIn(fence: Fence): Boolean = synchronized(lock) {
        current(fence) && prefs.getBoolean("user_opted_in", false) &&
            prefs.getString("consent_session", null) == fence.session
    }

    fun grant(fence: Fence): Boolean = synchronized(lock) {
        if (!current(fence)) return@synchronized false
        prefs.edit().putBoolean("user_opted_in", true).putString("consent_session", fence.session).commit()
    }

    fun confirm(fence: Fence, userId: String, token: String): Boolean = synchronized(lock) {
        if (!optedIn(fence) || !Regex("^[1-9][0-9]{0,18}$").matches(userId) || token.length !in 20..4096) return@synchronized false
        prefs.edit().putString("recipient_id", userId).putString("registration_hash", hash(token)).commit()
    }

    fun issue(fence: Fence, token: String): Fence? = synchronized(lock) {
        if (!optedIn(fence)) return@synchronized null
        val candidate = hash(token)
        if (prefs.getString("candidate_hash", null) != candidate) {
            check(prefs.edit().putString("candidate_hash", candidate)
                .putString("generation", UUID.randomUUID().toString()).commit())
        }
        Fence(fence.session, prefs.getString("generation", "").orEmpty())
    }

    fun clearConsent() = synchronized(lock) {
        // Local invalidation and cancellation precede every network operation.
        check(prefs.edit().remove("user_opted_in").remove("consent_session").remove("recipient_id")
            .remove("registration_hash").remove("candidate_hash").remove("seen").putString("generation", UUID.randomUUID().toString()).commit())
        cancelNotifications()
    }

    fun tokenChanged(token: String) = synchronized(lock) {
        val previous = prefs.getString("candidate_hash", null) ?: prefs.getString("registration_hash", null)
        if (previous == null || previous == hash(token)) return@synchronized
        // Keep same-session consent but require a new server acknowledgement.
        check(prefs.edit().remove("registration_hash").remove("candidate_hash").remove("seen")
            .putString("generation", UUID.randomUUID().toString()).commit())
        cancelNotifications()
    }

    fun installationId(): String = synchronized(lock) {
        val existing = prefs.getString("installation_id", null)
        if (!existing.isNullOrBlank()) return@synchronized existing
        val created = UUID.randomUUID().toString()
        check(prefs.edit().putString("installation_id", created).commit())
        created
    }

    fun allows(data: Map<String, String>): Boolean = synchronized(lock) {
        val session = prefs.getString("active_session", null) ?: return@synchronized false
        val generation = prefs.getString("generation", null) ?: return@synchronized false
        if (!optedIn(Fence(session, generation)) || !permissionGranted()) return@synchronized false
        if (data.keys != setOf("notification_id", "recipient_id", "registration_hash", "route")) return@synchronized false
        Regex("^[1-9][0-9]{0,18}$").matches(data["notification_id"].orEmpty()) &&
            data["recipient_id"] == prefs.getString("recipient_id", null) &&
            Regex("^[a-f0-9]{64}$").matches(data["registration_hash"].orEmpty()) &&
            data["registration_hash"] == prefs.getString("registration_hash", null) && allowedRoute(data["route"].orEmpty())
    }

    fun markSeen(id: String): Boolean = synchronized(lock) {
        val seen = prefs.getString("seen", "").orEmpty().split(',').filter { it.isNotBlank() }.toMutableList()
        if (id in seen) return@synchronized false
        seen.add(id)
        prefs.edit().putString("seen", seen.takeLast(100).joinToString(",")).commit()
    }

    fun permissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        return true
    }

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "إشعارات عقار", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    private fun cancelNotifications() {
        if (Build.VERSION.SDK_INT >= 23) manager.activeNotifications
            .filter { it.tag == NOTIFICATION_TAG }.forEach { manager.cancel(it.tag, it.id) }
    }
}
