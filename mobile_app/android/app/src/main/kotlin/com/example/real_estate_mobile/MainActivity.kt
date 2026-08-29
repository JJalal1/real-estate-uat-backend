package com.example.real_estate_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_CHANNEL = "real_estate/media"
        private const val SECURE_CHANNEL = "real_estate/secure_store"
        private const val PICK_IMAGES_REQUEST = 7419
        private const val TAKE_PHOTO_REQUEST = 7420
        private const val MAX_IMAGES = 12
        private const val KEY_ALIAS = "real_estate_stage6_auth_key"
        private const val PREFS_NAME = "real_estate_stage6_secure"
        private const val TOKEN_FIELD = "encrypted_auth_token"
        private const val GCM_TAG_BITS = 128
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingCameraFile: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> openImagePicker(result)
                    "takePhoto" -> openCamera(result)
                    "clearTemporaryFiles" -> clearTemporaryFiles(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
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
        }
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

    private fun copyUriToCache(uri: Uri, index: Int): String {
        val extension = when (contentResolver.getType(uri).orEmpty().lowercase()) {
            "image/png" -> ".png"
            "image/webp" -> ".webp"
            else -> ".jpg"
        }
        val directory = File(cacheDir, "stage5_uploads")
        if (!directory.exists()) directory.mkdirs()
        val output = File(directory, "stage5_${System.currentTimeMillis()}_${index}$extension")
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Unable to read selected image.")
        input.use { source -> FileOutputStream(output).use { destination -> source.copyTo(destination) } }
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
