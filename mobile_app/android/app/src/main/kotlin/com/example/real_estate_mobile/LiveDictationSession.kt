package com.example.real_estate_mobile

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/** In-app dictation. Recognition segments are previews until the user stops. */
class LiveDictationSession(
    private val activity: Activity,
    private val event: (String, Array<out Pair<String, Any>>) -> Unit,
    private val failure: (String) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private val completed = mutableListOf<String>()
    private var partial = ""
    private var spoke = false
    private var awaiting = false
    private var stopping = false
    private var disposed = false
    private var cycle = 0
    private val restart = Runnable { if (!stopping && !disposed) listen() }
    private val finishTimeout = Runnable { fail("SPEECH_NETWORK") }

    fun start() {
        try {
            recognizer = SpeechRecognizer.createSpeechRecognizer(activity)
            listen()
        } catch (_: SecurityException) { fail("SPEECH_PERMISSION") }
        catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
    }

    private fun text(tail: String = ""): String = (completed + tail).filter { it.isNotBlank() }.joinToString(" ")

    private fun preview(value: String) {
        if (value.length > 5000) { fail("SPEECH_TOO_LONG"); return }
        event("partial", arrayOf("text" to value))
    }

    private fun listen() {
        if (disposed || stopping || awaiting) return
        val engine = recognizer ?: return
        val segment = ++cycle
        partial = ""; spoke = false; awaiting = true
        engine.setRecognitionListener(object : RecognitionListener {
            private fun current(): Boolean = !disposed && segment == cycle && awaiting
            override fun onReadyForSpeech(params: Bundle?) {
                if (current() && !stopping) event("ready", emptyArray())
            }
            override fun onBeginningOfSpeech() { if (current()) spoke = true }
            override fun onRmsChanged(rmsdB: Float) {
                if (current() && !stopping) event("level", arrayOf("level" to ((rmsdB + 2) / 12.0).coerceIn(0.0, 1.0)))
            }
            override fun onPartialResults(results: Bundle?) {
                if (!current() || stopping) return
                partial = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty().trim()
                preview(text(partial))
            }
            override fun onResults(results: Bundle?) {
                if (!current()) return
                awaiting = false; ++cycle
                val value = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty().trim()
                // Never promote a partial hypothesis when a spoken segment is lost.
                if (value.isEmpty() && (spoke || partial.isNotEmpty())) { fail("SPEECH_NO_MATCH"); return }
                if (value.isNotEmpty()) completed.add(value)
                partial = ""
                if (text().length > 5000) { fail("SPEECH_TOO_LONG"); return }
                if (stopping) finish() else { preview(text()); handler.postDelayed(restart, 150L) }
            }
            override fun onError(error: Int) {
                if (!current()) return
                awaiting = false; ++cycle
                val silence = (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT || error == SpeechRecognizer.ERROR_NO_MATCH) && !spoke && partial.isEmpty()
                if (silence) {
                    if (stopping) finish() else handler.postDelayed(restart, 250L)
                } else fail(when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "SPEECH_PERMISSION"
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "SPEECH_NETWORK"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "SPEECH_BUSY"
                    SpeechRecognizer.ERROR_NO_MATCH -> "SPEECH_NO_MATCH"
                    else -> "SPEECH_UNAVAILABLE"
                })
            }
            override fun onEndOfSpeech() { /* Silence closes a segment, never this user session. */ }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        try {
            engine.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-YE")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            })
        } catch (_: SecurityException) { fail("SPEECH_PERMISSION") }
        catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
    }

    fun stop() {
        if (disposed || stopping) return
        stopping = true
        handler.removeCallbacks(restart)
        if (!awaiting) { finish(); return }
        handler.postDelayed(finishTimeout, 12000L)
        try { recognizer?.stopListening() } catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
    }

    private fun finish() {
        if (disposed || !stopping) return
        val result = text()
        if (result.isBlank()) { fail("SPEECH_NO_MATCH"); return }
        event("final", arrayOf("text" to result, "complete" to true))
        dispose()
    }

    private fun fail(code: String) { if (!disposed) { dispose(); failure(code) } }

    fun dispose() {
        if (disposed) return
        disposed = true; ++cycle; awaiting = false
        handler.removeCallbacks(restart); handler.removeCallbacks(finishTimeout)
        try { recognizer?.cancel() } catch (_: Exception) {}
        try { recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null; partial = ""; completed.clear()
    }
}
