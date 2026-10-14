package com.example.real_estate_mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Short, user-initiated dictation. All recognition UI is owned by Flutter. */
class InAppSpeechInput(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "real_estate/speech")
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var activeId: Int? = null
    private var permissionPending = false
    private var foreground = false
    private var processing = false
    private val permissionCode = 7421
    private val finalTimeout = Runnable { fail("SPEECH_TIMEOUT") }
    private val recordingTimeout = Runnable { stop() }

    init {
        channel.setMethodCallHandler { call, result ->
            val id = call.argument<Number>("id")?.toInt()
            if (id == null) {
                result.error("SPEECH_REQUEST", "Missing dictation identifier.", null)
            } else when (call.method) {
                "start" -> {
                    if (activeId != null || permissionPending) {
                        result.error("SPEECH_BUSY", "Dictation is already active.", null)
                    } else {
                        activeId = id
                        result.success(null)
                        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
                            fail("SPEECH_UNAVAILABLE")
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            permissionPending = true
                            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionCode)
                        } else begin()
                    }
                }
                "cancel" -> { if (id == activeId) cancel(); result.success(null) }
                "stop" -> { if (id == activeId) stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    fun onPermissionResult(code: Int, grants: IntArray) {
        if (code != permissionCode) return
        permissionPending = false
        if (activeId == null) return
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) begin()
        else fail("SPEECH_PERMISSION")
    }

    fun onResume() { foreground = true; if (!permissionPending && activeId != null && recognizer == null) begin() }
    fun onPause() { foreground = false; if (recognizer != null) cancel() }

    private fun begin() {
        val id = activeId ?: return
        if (!foreground || permissionPending || recognizer != null) return
        try {
            val engine = SpeechRecognizer.createSpeechRecognizer(activity)
            recognizer = engine
            processing = false
            engine.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { emit(id, "ready") }
                override fun onBeginningOfSpeech() { emit(id, "ready") }
                override fun onRmsChanged(rmsdB: Float) {
                    if (!processing) emit(id, "level", "level" to ((rmsdB + 2f) / 12f).coerceIn(0f, 1f).toDouble())
                }
                override fun onBufferReceived(buffer: ByteArray?) { /* No audio files or logs. */ }
                override fun onEndOfSpeech() { if (id == activeId) awaitingFinal(id) }
                override fun onPartialResults(results: Bundle?) { emit(id, "partial", "text" to transcript(results)) }
                override fun onResults(results: Bundle?) {
                    if (id != activeId) return
                    val text = transcript(results)
                    if (text.isBlank()) fail("SPEECH_NO_MATCH")
                    else { emit(id, "final", "text" to text); release() }
                }
                override fun onError(error: Int) {
                    if (id != activeId) return
                    fail(when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "SPEECH_PERMISSION"
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "SPEECH_NO_MATCH"
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "SPEECH_NETWORK"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "SPEECH_BUSY"
                        else -> "SPEECH_UNAVAILABLE"
                    })
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            // Configuration for startListening, never an Activity launch.
            engine.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-YE")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            })
            handler.postDelayed(recordingTimeout, 30000L)
        } catch (_: SecurityException) { fail("SPEECH_PERMISSION") }
        catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
    }

    private fun transcript(bundle: Bundle?): String =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()?.take(1500).orEmpty()

    private fun emit(id: Int, type: String, vararg values: Pair<String, Any>) {
        if (id == activeId) channel.invokeMethod("event", mapOf("id" to id, "type" to type) + values.toMap())
    }

    private fun awaitingFinal(id: Int) {
        if (processing || id != activeId) return
        processing = true
        handler.removeCallbacks(recordingTimeout)
        emit(id, "processing")
        handler.postDelayed(finalTimeout, 8000L)
    }

    private fun stop() {
        val id = activeId ?: return
        if (recognizer == null) { cancel(); return }
        if (processing) return
        try { awaitingFinal(id); recognizer?.stopListening() }
        catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
    }

    private fun fail(code: String) { activeId?.let { emit(it, "error", "code" to code) }; release() }
    private fun cancel() { activeId?.let { emit(it, "cancelled") }; release() }
    private fun release() {
        activeId = null
        processing = false
        handler.removeCallbacks(recordingTimeout)
        handler.removeCallbacks(finalTimeout)
        val engine = recognizer
        recognizer = null
        try { engine?.cancel() } catch (_: Exception) {}
        try { engine?.destroy() } catch (_: Exception) {}
    }
    fun dispose() { cancel(); channel.setMethodCallHandler(null) }
}
