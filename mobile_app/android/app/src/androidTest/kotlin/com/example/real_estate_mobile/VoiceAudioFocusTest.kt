package com.example.real_estate_mobile

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.media.AudioManager
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Actual foreground Android focus API. No microphone, ASR, or real music claims. */
class VoiceAudioFocusTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private var activity: Activity? = null
    private var focus: VoiceAudioFocus? = null
    private var competitor: VoiceAudioFocus? = null

    @Before fun openForegroundActivity() {
        activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        instrumentation.waitForIdleSync()
    }
    @After fun cleanup() {
        instrumentation.runOnMainSync { competitor?.release(); focus?.release(); activity?.finish() }
    }
    @Test fun temporaryFocusCanBeReleasedAndReacquiredWithoutChangingVolume() {
        instrumentation.runOnMainSync {
            val audio = activity!!.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val volume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            val current = VoiceAudioFocus(activity!!) {}
            focus = current
            assertTrue(current.acquire()); assertTrue(current.held)
            assertTrue(current.acquire())
            current.release(); current.release(); assertFalse(current.held)
            assertTrue(current.acquire()); current.release(); assertFalse(current.held)
            assertEquals(volume, audio.getStreamVolume(AudioManager.STREAM_MUSIC))
        }
    }
    @Test fun competingFocusCancelsTheCurrentCaptureAndReleasesItsLease() {
        val lost = CountDownLatch(1)
        instrumentation.runOnMainSync {
            focus = VoiceAudioFocus(activity!!) { lost.countDown() }
            assertTrue(focus!!.acquire())
            competitor = VoiceAudioFocus(activity!!) {}
            assertTrue(competitor!!.acquire())
        }
        assertTrue("Focus loss must reach the capture", lost.await(3, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { assertFalse(focus!!.held) }
    }
}
