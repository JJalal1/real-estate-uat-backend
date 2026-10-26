package com.example.real_estate_mobile

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch

/** Real Android storage/notification tests, with synthetic envelopes, NOT FCM delivery. */
class PushSessionIsolationTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val manager get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val token = "synthetic-fcm-token-for-isolation-only"
    private val session = "synthetic-session-A"
    private lateinit var state: PushSessionState

    @Before fun prepare() {
        context.getSharedPreferences("aqer_push", Context.MODE_PRIVATE).edit().clear().commit()
        state = PushSessionState(context)
        state.sessionChanged(session)
        if (Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        state.ensureChannel()
    }
    @After fun cleanup() { state.sessionChanged(null) }
    private fun fence() = state.capture(session, session)!!
    private fun enroll() { val f = fence(); assertTrue(state.grant(f)); assertTrue(state.confirm(f, "101", token)) }
    private fun data() = mapOf("notification_id" to "901", "recipient_id" to "101",
        "registration_hash" to PushSessionState.hash(token), "route" to "/messages/77")

    @Test fun noConsentOrAcknowledgementNeverDelivers() {
        assertFalse(state.allows(data()))
        assertTrue(state.grant(fence()))
        assertFalse(state.allows(data()))
    }
    @Test fun wrongSessionCannotGrantOrCapture() {
        assertNull(state.capture("wrong-session", session))
        assertNull(state.capture(session, null))
        assertFalse(state.confirm(PushSessionState.Fence("wrong", "wrong"), "101", token))
    }
    @Test fun changedAccountAndSameAccountNewSessionRejectOldEnvelope() {
        enroll(); assertTrue(state.allows(data()))
        state.sessionChanged("synthetic-session-B")
        assertFalse(state.allows(data()))
        state.sessionChanged(session)
        assertFalse(state.allows(data()))
    }
    @Test fun stalePermissionOrRegistrationCallbackCannotRestoreConsent() {
        val old = fence(); state.clearConsent()
        assertFalse(state.grant(old)); assertFalse(state.confirm(old, "101", token))
        assertFalse(state.allows(data()))
    }
    @Test fun recipientAndTokenMustBothMatch() {
        enroll()
        assertFalse(state.allows(data() + ("recipient_id" to "202")))
        assertFalse(state.allows(data() + ("registration_hash" to PushSessionState.hash("old-token"))))
    }
    @Test fun tokenRotationRequiresFreshServerAcknowledgement() {
        enroll(); state.tokenChanged("synthetic-fcm-token-rotated-only")
        assertFalse(state.allows(data()))
        assertTrue(state.optedIn(fence()))
        assertTrue(state.confirm(fence(), "101", "synthetic-fcm-token-rotated-only"))
        assertTrue(state.allows(data() + ("registration_hash" to PushSessionState.hash("synthetic-fcm-token-rotated-only"))))
    }
    @Test fun malformedAndUnexpectedPayloadsNeverDisplay() {
        enroll()
        for (invalid in listOf(data() - "recipient_id", data() + ("body" to "PRIVATE_SENTINEL"),
            data() + ("notification_id" to "-1"), data() + ("notification_id" to "1e9"),
            data() + ("route" to "https://evil.test"), data() + ("route" to "/messages/1?user=2"),
            data() + ("route" to "/admin"), data() + ("route" to "/messages/../admin"))) {
            assertFalse(PushMessageHandler.display(context, invalid))
        }
    }
    @Test fun duplicateSuppressionSurvivesNewStateInstance() {
        enroll(); assertTrue(PushMessageHandler.display(context, data()))
        assertFalse(PushSessionState(context).markSeen("901"))
        assertFalse(PushMessageHandler.display(context, data()))
    }
    @Test fun actualAndroidNotificationIsGenericAndRevocationRemovesIt() {
        enroll(); assertTrue(PushMessageHandler.display(context, data()))
        val active = manager.activeNotifications.single { it.tag == PushSessionState.NOTIFICATION_TAG }
        assertEquals("عقار", active.notification.extras.getString("android.title"))
        assertEquals("لديك إشعار جديد. افتح التطبيق لعرضه.", active.notification.extras.getString("android.text"))
        state.clearConsent()
        assertTrue(manager.activeNotifications.none { it.tag == PushSessionState.NOTIFICATION_TAG })
    }
    @Test fun delayedTokenReceiptCannotReplaceNewerRegistration() {
        val f = fence(); assertTrue(state.grant(f))
        val old = state.issue(f, token)!!
        val newer = state.issue(old, "synthetic-newer-token-for-isolation")!!
        assertFalse(state.confirm(old, "101", token))
        assertTrue(state.confirm(newer, "101", "synthetic-newer-token-for-isolation"))
        assertFalse(state.allows(data()))
    }
    @Test fun revocationAndReceiveCannotLeaveAnOldTrayNotification() {
        enroll()
        val start = CountDownLatch(1)
        val receive = Thread { start.await(); PushMessageHandler.display(context, data()) }
        val revoke = Thread { start.await(); state.clearConsent() }
        receive.start(); revoke.start(); start.countDown(); receive.join(); revoke.join()
        assertFalse(state.allows(data()))
        assertTrue(manager.activeNotifications.none { it.tag == PushSessionState.NOTIFICATION_TAG })
    }
    @Test fun storageContainsOnlyFingerprintsAndInstallationIdIsStable() {
        enroll(); val installation = state.installationId()
        val values = context.getSharedPreferences("aqer_push", Context.MODE_PRIVATE).all.values
        assertTrue(values.none { it == token || it == session })
        state.clearConsent()
        assertEquals(installation, PushSessionState(context).installationId())
    }
}
