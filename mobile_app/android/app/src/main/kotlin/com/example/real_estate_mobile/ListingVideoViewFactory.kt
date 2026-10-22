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
                video.setVideoURI(uri)
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
