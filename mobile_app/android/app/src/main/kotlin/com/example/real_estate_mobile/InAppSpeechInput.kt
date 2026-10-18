package com.example.real_estate_mobile

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.ln

/** Silence never finishes a recording. Only the explicit stop produces a clip. */
class InAppSpeechInput(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "real_estate/speech")
    private val handler = Handler(Looper.getMainLooper())
    private var recorder: MediaRecorder? = null
    private var dictation: LiveDictationSession? = null
    private var liveRequested = false
    private var clip: File? = null
    private var activeId: Int? = null
    private var permissionPending = false
    private var foreground = false
    private var processing = false
    private val permissionCode = 7421
    private val levels = object : Runnable {
        override fun run() {
            val id = activeId ?: return
            if (processing || recorder == null) return
            try {
                val amplitude = recorder?.maxAmplitude ?: 0
                emit(id, "level", "level" to (ln(1.0 + amplitude) / ln(32768.0)).coerceIn(0.0, 1.0))
                handler.postDelayed(this, 120L)
            } catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
        }
    }
    init {
        channel.setMethodCallHandler { call, result ->
            val id = call.argument<Number>("id")?.toInt()
            if (id == null) result.error("SPEECH_REQUEST", "Missing recording identifier.", null)
            else when (call.method) {
                "start" -> {
                    if (activeId != null || permissionPending) result.error("SPEECH_BUSY", "Recording already active.", null)
                    else {
                        activeId = id
                        liveRequested = call.argument<String>("mode") == "dictation"
                        result.success(null)
                        if (!foreground) cancel()
                        else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            permissionPending = true
                            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionCode)
                        } else begin()
                    }
                }
                "stop" -> { if (id == activeId) stop(); result.success(null) }
                "cancel" -> { if (id == activeId) cancel(); result.success(null) }
                "release" -> { if (id == activeId) release(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    fun onPermissionResult(code: Int, grants: IntArray) {
        if (code != permissionCode) return
        permissionPending = false
        if (activeId == null) return
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) begin() else fail("SPEECH_PERMISSION")
    }
    fun onResume() { foreground = true; if (!permissionPending && activeId != null && !processing && recorder == null && dictation == null) begin() }
    fun onPause() { foreground = false; if (!permissionPending) cancel() }
    @Suppress("DEPRECATION")
    private fun begin() {
        val id = activeId ?: return
        if (!foreground || permissionPending || recorder != null || dictation != null || processing) return
        try {
            if (liveRequested && SpeechRecognizer.isRecognitionAvailable(activity)) {
                emit(id, "mode", "code" to "dictation")
                val session = LiveDictationSession(activity,
                    event = { type, values -> emit(id, type, *values) },
                    failure = { code -> if (id == activeId) fail(code) })
                dictation = session
                session.start()
                return
            }
            emit(id, "mode", "code" to "clip")
            val file = File.createTempFile("re_voice_", ".m4a", activity.cacheDir)
            clip = file
            val engine = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(activity) else MediaRecorder()
            recorder = engine
            engine.setAudioSource(MediaRecorder.AudioSource.MIC)
            engine.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            engine.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            engine.setAudioChannels(1)
            engine.setAudioSamplingRate(16000)
            engine.setAudioEncodingBitRate(64000)
            engine.setOutputFile(file.absolutePath)
            // A resource limit is an explicit failure, never a partial search.
            engine.setMaxFileSize(8L * 1024 * 1024)
            engine.setOnInfoListener { _, what, _ ->
                if (id == activeId && what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) fail("SPEECH_TOO_LARGE")
            }
            engine.setOnErrorListener { _, _, _ -> if (id == activeId) fail("SPEECH_UNAVAILABLE") }
            engine.prepare()
            engine.start()
            emit(id, "ready")
            handler.post(levels)
        } catch (_: SecurityException) { fail("SPEECH_PERMISSION") }
        catch (_: Exception) { fail("SPEECH_UNAVAILABLE") }
    }
    private fun stop() {
        val id = activeId ?: return
        if (processing) return
        dictation?.let { processing = true; it.stop(); return }
        val engine = recorder ?: return
        processing = true
        handler.removeCallbacks(levels)
        try {
            engine.stop()
            engine.release()
            recorder = null
            val file = clip
            if (file == null || file.length() < 512) { fail("SPEECH_NO_MATCH"); return }
            emit(id, "recorded", "path" to file.absolutePath)
        } catch (_: Exception) { fail("SPEECH_NO_MATCH") }
    }
    private fun emit(id: Int, type: String, vararg values: Pair<String, Any>) {
        if (id == activeId) channel.invokeMethod("event", mapOf("id" to id, "type" to type) + values.toMap())
    }
    private fun fail(code: String) { activeId?.let { emit(it, "error", "code" to code) }; release() }
    private fun cancel() { activeId?.let { emit(it, "cancelled") }; release() }
    private fun release() {
        activeId = null
        processing = false
        handler.removeCallbacks(levels)
        dictation?.dispose()
        dictation = null
        try { recorder?.stop() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
        try { clip?.delete() } catch (_: Exception) {}
        clip = null
    }
    fun dispose() { cancel(); channel.setMethodCallHandler(null) }
}
