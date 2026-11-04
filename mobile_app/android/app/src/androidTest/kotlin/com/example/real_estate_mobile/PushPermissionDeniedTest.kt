package com.example.real_estate_mobile

import android.Manifest
import android.content.pm.PackageManager
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

/** Runs on a fresh API36 installation BEFORE the permission-granted group. */
class PushPermissionDeniedTest {
    @Test fun actualRuntimePermissionDenialPreventsDisplay() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(PackageManager.PERMISSION_DENIED, context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS))
        val state = PushSessionState(context)
        state.sessionChanged("synthetic-permission-session")
        val fence = state.capture("synthetic-permission-session", "synthetic-permission-session")!!
        assertTrue(state.grant(fence))
        assertTrue(state.confirm(fence, "101", "synthetic-permission-fcm-token"))
        assertFalse(PushMessageHandler.display(context, mapOf("notification_id" to "901", "recipient_id" to "101",
            "registration_hash" to PushSessionState.hash("synthetic-permission-fcm-token"), "route" to "/notifications")))
        state.sessionChanged(null)
    }
}
