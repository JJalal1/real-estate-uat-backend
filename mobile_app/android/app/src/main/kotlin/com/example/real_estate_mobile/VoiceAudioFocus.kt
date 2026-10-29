package com.example.real_estate_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/** Temporary microphone focus. Never changes global volume or resumes another player. */
class VoiceAudioFocus(context: Context, private val onLost: () -> Unit) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var request: AudioFocusRequest? = null
    var held: Boolean = false
        private set
    private val listener = AudioManager.OnAudioFocusChangeListener { change ->
        if (held && change < 0) { release(); onLost() }
    }

    @Suppress("DEPRECATION")
    fun acquire(): Boolean {
        if (held) return true
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(listener, Handler(Looper.getMainLooper())).build()
            request = focus
            audio.requestAudioFocus(focus)
        } else audio.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
        held = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!held) release()
        return held
    }

    @Suppress("DEPRECATION")
    fun release() {
        held = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) request?.let { audio.abandonAudioFocusRequest(it) }
        else audio.abandonAudioFocus(listener)
        request = null
    }
}
