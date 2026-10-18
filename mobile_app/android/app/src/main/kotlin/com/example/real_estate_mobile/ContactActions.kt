package com.example.real_estate_mobile

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Opens the dialer after a user tap. It never places a call or requests CALL_PHONE. */
class ContactActions(activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "real_estate/contact").setMethodCallHandler { call, result ->
            if (call.method != "openDialer") {
                result.notImplemented()
            } else {
                val phone = call.argument<String>("phone").orEmpty()
                if (!Regex("^\\+?[0-9]{7,15}$").matches(phone)) {
                    result.success(false)
                } else {
                    try {
                        activity.startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", phone, null)))
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                }
            }
        }
    }
}
