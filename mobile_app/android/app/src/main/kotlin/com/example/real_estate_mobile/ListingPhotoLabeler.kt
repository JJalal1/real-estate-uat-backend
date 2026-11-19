package com.example.real_estate_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.ExifInterface
import android.os.Build
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeler
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

internal class ListingPhotoLabeler(context: Context) {
    private val roots = listOf(
        File(context.cacheDir, "stage5_uploads"),
        File(context.noBackupFilesDir, "listing_recovery")
    ).map { it.canonicalPath + File.separator }
    private val worker = Executors.newSingleThreadExecutor()
    private var client: ImageLabeler? = null

    fun label(path: String?, result: MethodChannel.Result) {
        worker.execute {
            val file = path?.let { runCatching { File(it).canonicalFile }.getOrNull() }
            if (file == null || roots.none { file.path.startsWith(it) } || !file.isFile) {
                result.error("LISTING_PHOTO_UNREADABLE", null, null)
                return@execute
            }
            val image = runCatching { decode(file) }.getOrNull()
            if (image == null) {
                result.error("LISTING_PHOTO_UNREADABLE", null, null)
                return@execute
            }
            val (bitmap, rotation) = image
            try {
                val labeler = client ?: ImageLabeling.getClient(
                    ImageLabelerOptions.Builder().setConfidenceThreshold(0.45f).build()
                ).also { client = it }
                labeler.process(InputImage.fromBitmap(bitmap, rotation)).addOnCompleteListener { task ->
                    try {
                        if (task.isSuccessful) {
                            result.success(task.result.associate {
                                it.text.lowercase(Locale.ROOT) to it.confidence.toDouble()
                            })
                        } else {
                            result.error("LISTING_PHOTO_CHECK_UNAVAILABLE", null, null)
                        }
                    } finally {
                        bitmap.recycle()
                    }
                }
            } catch (_: Exception) {
                bitmap.recycle()
                result.error("LISTING_PHOTO_CHECK_UNAVAILABLE", null, null)
            }
        }
    }

    private fun decode(file: File): Pair<Bitmap, Int>? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.setTargetSampleSize(sampleSize(info.size.width, info.size.height))
            }
            return bitmap to 0
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
        }
        val rotation = runCatching {
            when (ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
                ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_TRANSPOSE -> 90
                ExifInterface.ORIENTATION_ROTATE_180, ExifInterface.ORIENTATION_FLIP_VERTICAL -> 180
                ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSVERSE -> 270
                else -> 0
            }
        }.getOrDefault(0)
        return BitmapFactory.decodeFile(file.path, options)?.let { it to rotation }
    }

    private fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        while (maxOf(width, height) / sample > 768) sample *= 2
        return sample
    }

    fun dispose() {
        worker.execute { client?.close() }
        worker.shutdown()
    }
}
