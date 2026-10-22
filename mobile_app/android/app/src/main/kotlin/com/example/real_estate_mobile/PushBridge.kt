package com.example.real_estate_mobile

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class PushBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "real_estate/push"
        const val PERMISSION_REQUEST = 7430
        private const val PREFS = "aqer_push"
        private const val INSTALLATION_ID = "installation_id"
        private const val NOTIFICATION_CHANNEL = "aqer_general"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingRoute: String? = routeFromIntent(activity.intent)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isConfigured" -> result.success(configured())
                "currentRegistration" -> currentRegistration(result)
                "requestRegistration" -> requestRegistration(result)
                "deleteToken" -> deleteToken(result)
                "consumeRoute" -> {
                    val route = pendingRoute
                    pendingRoute = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPermissionResult = null
    }

    fun onNewIntent(intent: Intent) {
        routeFromIntent(intent)?.let { pendingRoute = it }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = pendingPermissionResult
        pendingPermissionResult = null
        if (result == null) return true
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            result.success(status(configured = configured(), granted = false))
            return true
        }
        resolveToken(result)
        return true
    }

    private fun routeFromIntent(intent: Intent?): String? {
        val explicit = intent?.getStringExtra("route")?.trim().orEmpty()
        if (explicit.startsWith("/") && explicit.length <= 300) return explicit

        val type = intent?.getStringExtra("entity_type")?.trim().orEmpty()
        val id = intent?.getStringExtra("entity_id")?.toIntOrNull() ?: 0
        if (id > 0 && (type == "property" || type == "listing")) return "/properties/$id"
        if (id > 0 && (type == "message_thread" || type == "conversation")) return "/messages/$id"
        return null
    }

    private fun requestRegistration(result: MethodChannel.Result) {
        if (!configured()) {
            result.success(status(configured = false, granted = false))
            return
        }
        initializeFirebase()
        ensureNotificationChannel()

        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (pendingPermissionResult != null) {
                result.error("PUSH_PERMISSION_BUSY", "Notification permission request is already open.", null)
                return
            }
            pendingPermissionResult = result
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST,
            )
            return
        }
        resolveToken(result)
    }

    private fun currentRegistration(result: MethodChannel.Result) {
        if (!configured()) {
            result.success(status(configured = false, granted = false))
            return
        }
        initializeFirebase()
        ensureNotificationChannel()
        if (!permissionGranted()) {
            result.success(status(configured = true, granted = false))
            return
        }
        resolveToken(result)
    }

    private fun resolveToken(result: MethodChannel.Result) {
        try {
            initializeFirebase()
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    result.error("PUSH_TOKEN_FAILED", task.exception?.message, null)
                    return@addOnCompleteListener
                }
                val token = task.result?.trim().orEmpty()
                if (token.isEmpty()) {
                    result.error("PUSH_TOKEN_EMPTY", "Firebase did not return a device token.", null)
                    return@addOnCompleteListener
                }
                result.success(
                    mapOf(
                        "configured" to true,
                        "granted" to true,
                        "token" to token,
                        "installation_id" to installationId(),
                    ),
                )
            }
        } catch (error: Exception) {
            result.error("PUSH_INIT_FAILED", error.message, null)
        }
    }

    private fun deleteToken(result: MethodChannel.Result) {
        if (!configured()) {
            result.success(null)
            return
        }
        try {
            initializeFirebase()
            FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { task ->
                if (task.isSuccessful) result.success(null)
                else result.error("PUSH_DELETE_FAILED", task.exception?.message, null)
            }
        } catch (error: Exception) {
            result.error("PUSH_DELETE_FAILED", error.message, null)
        }
    }

    private fun configured(): Boolean =
        BuildConfig.AQER_PUSH_ENABLED &&
            BuildConfig.AQER_FIREBASE_API_KEY.isNotBlank() &&
            BuildConfig.AQER_FIREBASE_APP_ID.isNotBlank() &&
            BuildConfig.AQER_FIREBASE_PROJECT_ID.isNotBlank() &&
            BuildConfig.AQER_FIREBASE_SENDER_ID.isNotBlank()

    private fun permissionGranted(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun initializeFirebase() {
        if (!configured()) throw IllegalStateException("Push notifications are not configured.")
        if (FirebaseApp.getApps(activity).isNotEmpty()) return
        val options = FirebaseOptions.Builder()
            .setApiKey(BuildConfig.AQER_FIREBASE_API_KEY)
            .setApplicationId(BuildConfig.AQER_FIREBASE_APP_ID)
            .setProjectId(BuildConfig.AQER_FIREBASE_PROJECT_ID)
            .setGcmSenderId(BuildConfig.AQER_FIREBASE_SENDER_ID)
            .build()
        FirebaseApp.initializeApp(activity, options)
            ?: throw IllegalStateException("Firebase initialization failed.")
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "إشعارات عقار",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "رسائل وتنبيهات عقار المهمة"
            },
        )
    }

    private fun installationId(): String {
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(INSTALLATION_ID, null)?.trim()
        if (!existing.isNullOrEmpty()) return existing
        val created = UUID.randomUUID().toString()
        prefs.edit().putString(INSTALLATION_ID, created).apply()
        return created
    }

    private fun status(configured: Boolean, granted: Boolean): Map<String, Any> =
        mapOf(
            "configured" to configured,
            "granted" to granted,
            "installation_id" to installationId(),
        )
}
