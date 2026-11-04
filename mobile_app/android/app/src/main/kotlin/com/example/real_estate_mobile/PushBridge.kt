package com.example.real_estate_mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PushBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val currentSessionToken: () -> String?,
) {
    companion object {
        const val CHANNEL = "real_estate/push"
        const val PERMISSION_REQUEST = 7430
        var onRegistrationChanged: (() -> Unit)? = null
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val state = PushSessionState(activity)
    private var pendingPermission: Pair<MethodChannel.Result, PushSessionState.Fence>? = null
    private var pendingEnvelope: Map<String, String>? = envelope(activity.intent)
    private var disposed = false
    private var deletingToken: com.google.android.gms.tasks.Task<Void>? = null

    init {
        onRegistrationChanged = { if (!disposed) channel.invokeMethod("registrationChanged", null) }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isConfigured" -> result.success(configured())
                    "currentRegistration", "requestRegistration" -> registration(call, result)
                    "confirmRegistration" -> confirm(call, result)
                    "deleteToken" -> revoke(result)
                    "consumeRoute" -> {
                        val data = pendingEnvelope
                        pendingEnvelope = null
                        result.success(if (data != null && state.allows(data)) data["route"] else null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("PUSH_UNAVAILABLE", "Push operation failed safely.", null)
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        onRegistrationChanged = null
        pendingPermission?.first?.error("PUSH_CANCELLED", "Push request cancelled.", null)
        pendingPermission = null
    }

    fun onNewIntent(intent: Intent) {
        pendingEnvelope = envelope(intent)
        if (pendingEnvelope != null && !disposed) channel.invokeMethod("notificationOpened", null)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val pending = pendingPermission
        pendingPermission = null
        if (pending == null) return true
        if (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            pending.first.success(status(false))
        } else resolveToken(pending.first, pending.second, true)
        return true
    }

    private fun envelope(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        val keys = listOf("notification_id", "recipient_id", "registration_hash", "route")
        val data = keys.associateWith { intent.getStringExtra("aqer_push_$it").orEmpty() }
        keys.forEach { intent.removeExtra("aqer_push_$it") }
        return if (state.allows(data)) data else null
    }

    private fun fence(call: MethodCall): PushSessionState.Fence? =
        state.capture(call.argument<String>("session_token").orEmpty(), currentSessionToken())

    private fun registration(call: MethodCall, result: MethodChannel.Result) {
        if (!configured()) { result.success(status(false)); return }
        val captured = fence(call)
        if (captured == null) { result.success(status(false)); return }
        val requested = call.method == "requestRegistration"
        if (!requested && !state.optedIn(captured)) { result.success(status(false)); return }
        initializeFirebase()
        state.ensureChannel()
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (!requested) { result.success(status(false)); return }
            if (pendingPermission != null) { result.error("PUSH_PERMISSION_BUSY", "A permission request is already open.", null); return }
            pendingPermission = Pair(result, captured)
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
            return
        }
        if (!state.permissionGranted()) { result.success(status(false)); return }
        resolveToken(result, captured, requested)
    }

    private fun resolveToken(result: MethodChannel.Result, captured: PushSessionState.Fence, rememberConsent: Boolean) {
        if (disposed || !state.current(captured) || !state.permissionGranted()) { result.success(status(false)); return }
        val deleting = deletingToken
        if (deleting != null && !deleting.isComplete) {
            deleting.addOnCompleteListener { resolveToken(result, captured, rememberConsent) }
            return
        }
        initializeFirebase()
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (disposed || !state.current(captured) || !state.permissionGranted()) { result.success(status(false)); return@addOnCompleteListener }
            val token = if (task.isSuccessful) task.result?.trim().orEmpty() else ""
            if (token.length !in 20..4096) { result.error("PUSH_TOKEN_FAILED", "Device registration is unavailable.", null); return@addOnCompleteListener }
            if (rememberConsent && !state.grant(captured)) { result.success(status(false)); return@addOnCompleteListener }
            if (!state.optedIn(captured)) { result.success(status(false)); return@addOnCompleteListener }
            val issued = state.issue(captured, token)
            if (issued == null) { result.success(status(false)); return@addOnCompleteListener }
            result.success(status(true) + mapOf("token" to token, "generation" to issued.generation))
        }
    }

    private fun confirm(call: MethodCall, result: MethodChannel.Result) {
        val captured = fence(call)
        val matches = captured != null && captured.generation == call.argument<String>("generation") &&
            state.permissionGranted() && state.confirm(captured, call.argument<String>("user_id").orEmpty(), call.argument<String>("token").orEmpty())
        result.success(matches)
    }

    private fun revoke(result: MethodChannel.Result) {
        state.clearConsent()
        pendingEnvelope = null
        val pending = pendingPermission
        pendingPermission = null
        pending?.first?.success(status(false))
        // Invalidate locally before networking; new enrollment waits for delete.
        if (configured()) {
            try {
                initializeFirebase()
                deletingToken = FirebaseMessaging.getInstance().deleteToken()
            } catch (_: Exception) { /* Local revocation is already durable. */ }
        }
        result.success(status(false))
    }

    private fun status(granted: Boolean): Map<String, Any> = mapOf(
        "configured" to configured(), "granted" to granted, "installation_id" to state.installationId(),
    )

    private fun configured(): Boolean = PushFirebase.configured()

    private fun initializeFirebase() {
        PushFirebase.initialize(activity)
    }
}
