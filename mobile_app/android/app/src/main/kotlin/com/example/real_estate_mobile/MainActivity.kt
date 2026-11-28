package com.example.real_estate_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.MediaStore
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_CHANNEL = "real_estate/media"
        private const val SECURE_CHANNEL = "real_estate/secure_store"
        private const val SHARE_CHANNEL = "real_estate/share"
        private const val LISTING_PREVIEW_NAVIGATION_CHANNEL = "real_estate/listing_preview_navigation"
        private const val PICK_IMAGES_REQUEST = 7419
        private const val TAKE_PHOTO_REQUEST = 7420
        private const val PICK_SUPPORT_EVIDENCE_REQUEST = 7421
        private const val MAX_IMAGES = 12
        private const val KEY_ALIAS = "real_estate_stage6_auth_key"
        private const val PREFS_NAME = "real_estate_stage6_secure"
        private const val TOKEN_FIELD = "encrypted_auth_token"
        private const val GCM_TAG_BITS = 128
    }

    private val offlineCrypto = Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingCameraFile: File? = null
    private var speechInput: InAppSpeechInput? = null
    private var pushBridge: PushBridge? = null
    private var listingPhotoLabeler: ListingPhotoLabeler? = null
    private var previousSystemBarsBehavior: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ContactActions(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LISTING_PREVIEW_NAVIGATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "setHidden") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val hidden = (call.arguments as? Map<*, *>)?.get("hidden") as? Boolean
                if (hidden == null) {
                    result.error("INVALID_ARGUMENT", "Expected a boolean hidden value.", null)
                    return@setMethodCallHandler
                }
                setListingPreviewNavigationHidden(hidden)
                result.success(null)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "real_estate/network")
            .setMethodCallHandler { call, result ->
                if (call.method == "uatNetworkTrace" && BuildConfig.FLAVOR == "uat") {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val allowed = setOf("resource", "phase", "scope", "seq", "page", "media", "variant", "bytes", "elapsedMs", "status")
                    val valid = values.isNotEmpty() && values.keys.all { it in allowed } && values.all { (key, value) ->
                        if (key == "variant") value is String && value in setOf("thumb", "card", "preview", "detail", "gallery", "zoom")
                        else value is Number && value.toLong() in 0L..1000000000L
                    }
                    if (valid) Log.i("AQER_NET", JSONObject(values).toString())
                    result.success(null)
                } else if (call.method == "imagePrefetchMetrics" && BuildConfig.FLAVOR == "uat") {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val metrics = JSONObject()
                    for (key in listOf("enabled", "requests", "bytes", "readyHits", "scope", "metered", "dataSaver", "eligible")) {
                        val value = values[key]
                        if (value is Boolean || (value is Number && value.toLong() in -1L..1000000000L)) metrics.put(key, value)
                    }
                    Log.i("AQER_PREFETCH", metrics.toString())
                    result.success(null)
                } else if (call.method != "imageNetworkState") {
                    result.notImplemented()
                } else {
                    val manager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    val network = manager.activeNetwork
                    val capabilities = manager.getNetworkCapabilities(network)
                    val saver = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                        manager.restrictBackgroundStatus != ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED
                    val transport = when {
                        capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> "wifi"
                        capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> "cellular"
                        else -> "other"
                    }
                    val validated = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
                    result.success(mapOf("metered" to manager.isActiveNetworkMetered,
                        "dataSaver" to saver, "networkAvailable" to (network != null),
                        "validated" to validated, "connected" to validated, "networkKey" to (network?.toString() ?: "none"),
                        "transport" to transport))
                }
            }

        speechInput?.dispose()
        speechInput = InAppSpeechInput(this, flutterEngine.dartExecutor.binaryMessenger)

        pushBridge?.dispose()
        pushBridge = PushBridge(this, flutterEngine.dartExecutor.binaryMessenger, ::readSecureToken)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> openImagePicker(result)
                    "pickSupportEvidence" -> openSupportEvidencePicker(result)
                    "renderSupportPdf" -> renderSupportPdf(call.argument<String>("path"), call.argument<Int>("page") ?: 0, result)
                    "takePhoto" -> openCamera(result)
                    "labelListingPhoto" -> {
                        val labeler = listingPhotoLabeler ?: ListingPhotoLabeler(this).also {
                            listingPhotoLabeler = it
                        }
                        labeler.label(call.argument<String>("path"), result)
                    }
                    "clearTemporaryFiles" -> clearTemporaryFiles(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> {
                        val text = call.argument<String>("text").orEmpty().trim()
                        if (text.isEmpty()) {
                            result.error("SHARE_EMPTY", "Nothing to share.", null)
                            return@setMethodCallHandler
                        }
                        val subject = call.argument<String>("subject")?.trim().orEmpty()
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                            if (subject.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
                        }
                        try {
                            startActivity(Intent.createChooser(send, "مشاركة عبر"))
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("SHARE_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "sealOfflineState", "openOfflineState" -> {
                            val value = call.argument<String>("value").orEmpty()
                            require(value.length <= 2 * 1024 * 1024) { "Offline state exceeds its bound." }
                            offlineCrypto.execute {
                                try {
                                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                    val output: String
                                    if (call.method == "sealOfflineState") {
                                        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
                                        cipher.updateAAD("aqer.offline.v1".toByteArray(Charsets.UTF_8))
                                        val encoded = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                                        output = Base64.encodeToString(cipher.iv + encoded, Base64.NO_WRAP)
                                    } else {
                                        val bytes = Base64.decode(value, Base64.NO_WRAP)
                                        require(bytes.size > 28) { "Invalid offline state." }
                                        cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, bytes.copyOfRange(0, 12)))
                                        cipher.updateAAD("aqer.offline.v1".toByteArray(Charsets.UTF_8))
                                        output = String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
                                    }
                                    runOnUiThread { result.success(output) }
                                } catch (_: Exception) { runOnUiThread { result.error("OFFLINE_STORAGE_FAILED", "Offline state unavailable.", null) } }
                            }
                        }
                        "readToken" -> result.success(readSecureToken())
                        "writeToken" -> {
                            val token = call.argument<String>("token").orEmpty()
                            require(token.isNotBlank()) { "Token must not be empty." }
                            writeSecureToken(token)
                            result.success(null)
                        }
                        "deleteToken" -> {
                            deleteSecureToken()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("SECURE_STORAGE_FAILED", error.message, null)
                }
            }
    }

    private fun setListingPreviewNavigationHidden(hidden: Boolean) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val navigationBars = WindowInsetsCompat.Type.navigationBars()
        if (hidden) {
            if (previousSystemBarsBehavior == null) {
                previousSystemBarsBehavior = controller.systemBarsBehavior
            }
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(navigationBars)
        } else {
            val previousBehavior = previousSystemBarsBehavior ?: return
            controller.show(navigationBars)
            controller.systemBarsBehavior = previousBehavior
            previousSystemBarsBehavior = null
        }
    }

    @Synchronized
    private fun getOrCreateSecretKey(): SecretKey {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw IllegalStateException("Secure session storage requires Android 6.0 or newer.")
        }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun writeSecureToken(token: String) {
        PushSessionState(this).sessionChanged(token)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        require(cipher.iv.size in 1..255) { "Unexpected GCM IV length." }
        val payload = ByteArray(1 + cipher.iv.size + encrypted.size)
        payload[0] = cipher.iv.size.toByte()
        System.arraycopy(cipher.iv, 0, payload, 1, cipher.iv.size)
        System.arraycopy(encrypted, 0, payload, 1 + cipher.iv.size, encrypted.size)
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(TOKEN_FIELD, Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
    }

    private fun readSecureToken(): String? {
        val encoded = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(TOKEN_FIELD, null)
            ?: return null
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        if (payload.size < 2) {
            deleteSecureToken()
            return null
        }
        val ivLength = payload[0].toInt() and 0xFF
        if (ivLength <= 0 || payload.size <= 1 + ivLength) {
            deleteSecureToken()
            return null
        }
        return try {
            val iv = payload.copyOfRange(1, 1 + ivLength)
            val encrypted = payload.copyOfRange(1 + ivLength, payload.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (_: Exception) {
            deleteSecureToken()
            null
        }
    }

    private fun deleteSecureToken() {
        PushSessionState(this).sessionChanged(null)
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().remove(TOKEN_FIELD).apply()
    }

    private fun openImagePicker(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICKER_BUSY", "The image picker is already open.", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, PICK_IMAGES_REQUEST)
    }

    private fun openCamera(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICKER_BUSY", "The media picker is already open.", null)
            return
        }

        val directory = File(cacheDir, "stage5_uploads")
        if (!directory.exists() && !directory.mkdirs()) {
            result.error("CAMERA_CACHE_FAILED", "Unable to prepare the temporary camera folder.", null)
            return
        }

        val output = File(directory, "selfie_${System.currentTimeMillis()}.jpg")
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", output)
        } catch (error: Exception) {
            result.error("CAMERA_FILE_FAILED", error.message, null)
            return
        }

        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) {
            output.delete()
            result.error("CAMERA_UNAVAILABLE", "No camera application is available.", null)
            return
        }

        pendingResult = result
        pendingCameraFile = output
        try {
            startActivityForResult(intent, TAKE_PHOTO_REQUEST)
        } catch (error: Exception) {
            pendingResult = null
            pendingCameraFile = null
            output.delete()
            result.error("CAMERA_OPEN_FAILED", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android SDK but required by the current FlutterActivity API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            PICK_IMAGES_REQUEST -> handleImagePickerResult(resultCode, data)
            TAKE_PHOTO_REQUEST -> handleCameraResult(resultCode)
            PICK_SUPPORT_EVIDENCE_REQUEST -> handleSupportEvidence(resultCode, data?.data)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (pushBridge?.onPermissionResult(requestCode, grantResults) == true) return
        speechInput?.onPermissionResult(requestCode, grantResults)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pushBridge?.onNewIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        speechInput?.onResume()
    }

    override fun onPause() {
        speechInput?.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        offlineCrypto.shutdown()
        listingPhotoLabeler?.dispose()
        listingPhotoLabeler = null
        pushBridge?.dispose()
        pushBridge = null
        speechInput?.dispose()
        speechInput = null
        super.onDestroy()
    }

    private fun handleImagePickerResult(resultCode: Int, data: Intent?) {
        val result = pendingResult
        pendingResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        try {
            val uris = mutableListOf<Uri>()
            val clipData = data.clipData
            if (clipData != null) {
                val count = minOf(clipData.itemCount, MAX_IMAGES)
                for (index in 0 until count) uris.add(clipData.getItemAt(index).uri)
            } else {
                data.data?.let { uris.add(it) }
            }
            result.success(uris.take(MAX_IMAGES).mapIndexed { index, uri -> copyUriToCache(uri, index) })
        } catch (error: Exception) {
            result.error("PICKER_COPY_FAILED", error.message, null)
        }
    }

    private fun handleCameraResult(resultCode: Int) {
        val result = pendingResult
        val output = pendingCameraFile
        pendingResult = null
        pendingCameraFile = null
        if (result == null) {
            if (resultCode != Activity.RESULT_OK) output?.delete()
            return
        }
        if (resultCode != Activity.RESULT_OK || output == null || !output.isFile || output.length() <= 0) {
            output?.delete()
            result.success(null)
            return
        }
        result.success(output.absolutePath)
    }

    private fun openSupportEvidencePicker(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICKER_BUSY", "The media picker is already open.", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/pdf", "image/jpeg", "image/png", "image/webp"))
        }
        try {
            startActivityForResult(intent, PICK_SUPPORT_EVIDENCE_REQUEST)
        } catch (_: Exception) {
            pendingResult = null
            result.error("PICKER_UNAVAILABLE", "Cannot open the file picker.", null)
        }
    }

    private fun handleSupportEvidence(resultCode: Int, uri: Uri?) {
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        Thread {
            try {
                val path = copyUriToCache(uri, 0, 8L * 1024 * 1024)
                runOnUiThread { result.success(path) }
            } catch (_: Exception) {
                runOnUiThread { result.error("PICKER_COPY_FAILED", "Cannot copy the selected evidence.", null) }
            }
        }.start()
    }

    private fun renderSupportPdf(path: String?, page: Int, result: MethodChannel.Result) {
        Thread {
            try {
                val directory = File(cacheDir, "stage5_uploads").canonicalFile
                val pdf = File(path.orEmpty()).canonicalFile
                require(pdf.parentFile == directory && pdf.name.startsWith("support-preview-") && pdf.extension == "pdf")
                val descriptor = android.os.ParcelFileDescriptor.open(pdf, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
                val pdfRenderer = try {
                    android.graphics.pdf.PdfRenderer(descriptor)
                } catch (error: Exception) {
                    descriptor.close()
                    throw error
                }
                pdfRenderer.use { renderer ->
                    require(page in 0 until renderer.pageCount)
                    renderer.openPage(page).use { source ->
                        val scale = minOf(1000.0 / source.width, 1600.0 / source.height)
                        val bitmap = android.graphics.Bitmap.createBitmap(
                            (source.width * scale).toInt().coerceAtLeast(1),
                            (source.height * scale).toInt().coerceAtLeast(1),
                            android.graphics.Bitmap.Config.ARGB_8888
                        )
                        try {
                            bitmap.eraseColor(android.graphics.Color.WHITE)
                            source.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val stream = java.io.ByteArrayOutputStream()
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                            val data = mapOf("pages" to renderer.pageCount, "bytes" to stream.toByteArray())
                            runOnUiThread { result.success(data) }
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
            } catch (_: Exception) {
                runOnUiThread { result.error("PDF_PREVIEW_FAILED", "Cannot preview the document.", null) }
            }
        }.start()
    }

    private fun copyUriToCache(uri: Uri, index: Int, limit: Long? = null): String {
        val extension = when (contentResolver.getType(uri).orEmpty().lowercase()) {
            "image/png" -> ".png"
            "image/webp" -> ".webp"
            "image/jpeg", "image/jpg" -> ".jpg"
            "image/heic" -> ".heic"
            "image/heif" -> ".heif"
            "image/avif" -> ".avif"
            "image/gif" -> ".gif"
            "application/pdf" -> ".pdf"
            else -> ".bin"
        }
        val directory = File(cacheDir, "stage5_uploads")
        if (!directory.exists()) directory.mkdirs()
        val output = File(directory, "stage5_${System.currentTimeMillis()}_${index}$extension")
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Unable to read selected image.")
        try {
            input.use { source -> FileOutputStream(output).use { destination ->
                if (limit == null) {
                    source.copyTo(destination)
                } else {
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= limit)
                        destination.write(buffer, 0, count)
                    }
                    require(total > 0)
                }
            } }
        } catch (error: Exception) {
            output.delete()
            throw error
        }
        return output.absolutePath
    }

    private fun clearTemporaryFiles(arguments: Any?, result: MethodChannel.Result) {
        val values = (arguments as? Map<*, *>)?.get("paths") as? List<*>
        val cacheRoot = File(cacheDir, "stage5_uploads").canonicalFile
        try {
            values.orEmpty().forEach { raw ->
                val path = raw as? String ?: return@forEach
                val file = File(path).canonicalFile
                val inside = file.path == cacheRoot.path ||
                    file.path.startsWith(cacheRoot.path + File.separator)
                if (inside && file.isFile) file.delete()
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("CACHE_CLEANUP_FAILED", error.message, null)
        }
    }
}
