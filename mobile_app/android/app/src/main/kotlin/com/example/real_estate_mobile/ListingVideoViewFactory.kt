package com.example.real_estate_mobile

import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.VideoView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Private-original-free playback of transcoded MP4s. VideoView is created
 * only after Flutter's explicit play action and stops on widget disposal.
 */
class ListingVideoViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *>
        val url = (parameters?.get("url") as? String).orEmpty()
        val uri = Uri.parse(url)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank()) { "HTTPS video required" }
        val rawHeaders = parameters?.get("headers") as? Map<*, *>
        val bearer = rawHeaders?.get("Authorization") as? String
        require(bearer == null || (
            bearer.startsWith("Bearer ") &&
            bearer.length in 10..2048 &&
            bearer.all { it.code in 32..126 }
        )) { "Invalid media authorization" }
        if (bearer != null) {
            // Defense in depth: Flutter also validates these values before
            // handing over its session. Native code refuses to send a bearer
            // to any other origin, URI with query/fragment, or non-video route.
            val allowedOrigin = Uri.parse(
                (parameters?.get("apiOrigin") as? String).orEmpty()
            )
            require(
                allowedOrigin.scheme == "https" &&
                allowedOrigin.host == uri.host &&
                allowedOrigin.port == uri.port &&
                uri.userInfo.isNullOrEmpty() &&
                uri.query == null && uri.fragment == null &&
                Regex("^/api/property-videos/[1-9][0-9]*/stream$")
                    .matches(uri.path.orEmpty())
            ) { "Protected video must use the exact API media route" }
        }
        val mediaHeaders = if (bearer != null)
            mapOf("Authorization" to bearer, "android-allow-cross-domain-redirect" to "0")
        else null

        return object : PlatformView {
            val container = FrameLayout(context)
            val video = VideoView(context)
            init {
                container.addView(video, FrameLayout.LayoutParams(-1, -1))
                val controls = MediaController(context)
                controls.setAnchorView(video)
                video.setMediaController(controls)
                video.setOnPreparedListener { player ->
                    player.isLooping = false
                    player.setOnInfoListener { _, _, _ -> false }
                    video.start()
                }
                if (mediaHeaders != null) video.setVideoURI(uri, mediaHeaders)
                else video.setVideoURI(uri)
            }

            override fun getView(): View = container

            override fun dispose() {
                video.stopPlayback()
                video.setOnPreparedListener(null)
                video.setOnErrorListener(null)
                video.setMediaController(null)
                container.removeAllViews()
            }
        }
    }
}
