package com.meowwatch.meowwatch_mobile

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Window-only presentation; it never owns or restarts the media player. */
class FullscreenBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.meowwatch.mobile/fullscreen")
    private var enabled = false
    private var previousOrientation: Int? = null
    private var previousBarsBehavior: Int? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
            } else if (call.arguments !is Boolean) {
                result.error("invalid_fullscreen", "Expected a fullscreen boolean.", null)
            } else {
                try {
                    setEnabled(call.arguments as Boolean)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("fullscreen_unavailable", "Could not change fullscreen mode.", null)
                }
            }
        }
    }

    private fun setEnabled(value: Boolean) {
        val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
        if (value) {
            if (!enabled) {
                previousOrientation = activity.requestedOrientation
                previousBarsBehavior = controller.systemBarsBehavior
                enabled = true
            }
            // Large screens retain their orientation, including Android 16's
            // adaptive-layout behavior. Handsets prefer landscape for playback.
            if (activity.resources.configuration.smallestScreenWidthDp < 600) {
                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
            previousBarsBehavior?.let { controller.systemBarsBehavior = it }
            previousOrientation?.let { activity.requestedOrientation = it }
            previousOrientation = null
            previousBarsBehavior = null
            enabled = false
        }
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        if (hasFocus && enabled) {
            WindowCompat.getInsetsController(activity.window, activity.window.decorView)
                .hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (enabled) setEnabled(false)
    }
}
