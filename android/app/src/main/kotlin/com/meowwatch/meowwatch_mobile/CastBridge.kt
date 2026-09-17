package com.meowwatch.meowwatch_mobile

import android.os.Handler
import android.os.Looper
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteButton
import androidx.mediarouter.app.MediaRouteChooserDialogFragment
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.api.PendingResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.TimeUnit

/** No receiver URL, credentials, or raw SDK error text is emitted to Dart diagnostics. */
class CastBridge(private val activity: FlutterFragmentActivity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "com.meowwatch.mobile/cast")
    private val events = EventChannel(messenger, "com.meowwatch.mobile/cast/events")
    private val handler = Handler(Looper.getMainLooper())
    private var context: CastContext? = null
    private var session: CastSession? = null
    private var client: RemoteMediaClient? = null
    private var callback: RemoteMediaClient.Callback? = null
    private var progress: RemoteMediaClient.ProgressListener? = null
    private var sink: EventChannel.EventSink? = null
    private var chooser: MediaRouteChooserDialogFragment? = null
    private var pendingConnect: MethodChannel.Result? = null
    private var pendingConnectOwner: String? = null
    private var currentOwner: String? = null
    private var pendingDisconnect: MethodChannel.Result? = null
    private var generation = 0L
    private var revision = 0L
    private var connection = "disconnected"
    private var closed = false
    private val pendingCommands = mutableSetOf<MethodChannel.Result>()

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    private val connectTimeout = Runnable {
        failConnect("cast_timeout", "The TV did not connect. Try again.")
        chooser?.dismissAllowingStateLoss()
        context?.sessionManager?.endCurrentSession(true)
    }

    private val disconnectTimeout = Runnable {
        val result = pendingDisconnect
        pendingDisconnect = null
        result?.error("cast_timeout", "The TV has not confirmed disconnection. Check its Cast controls.", null)
    }

    private val listener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(value: CastSession) = starting(value)
        override fun onSessionResuming(value: CastSession, id: String) = starting(value)
        override fun onSessionStarted(value: CastSession, id: String) = connected(value)
        override fun onSessionResumed(value: CastSession, suspended: Boolean) = connected(value)
        override fun onSessionStartFailed(value: CastSession, error: Int) = lost(value, "failed")
        override fun onSessionResumeFailed(value: CastSession, error: Int) = lost(value, "failed")
        override fun onSessionSuspended(value: CastSession, reason: Int) = lost(value, "suspended")
        override fun onSessionEnding(value: CastSession) = lost(value, "disconnected")
        override fun onSessionEnded(value: CastSession, error: Int) {
            if (session !== value) return
            lost(value, "disconnected")
            val result = pendingDisconnect
            pendingDisconnect = null
            handler.removeCallbacks(disconnectTimeout)
            result?.success(state())
        }
    }

    private fun initialize(): CastContext {
        context?.let { return it }
        val next = CastContext.getSharedInstance(activity)
        context = next
        next.sessionManager.addSessionManagerListener(listener, CastSession::class.java)
        next.sessionManager.currentCastSession?.let {
            session = it
            generation++
            if (it.isConnected) connected(it)
        }
        return next
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        try {
            initialize()
            emit()
        } catch (_: Exception) {
            sink?.error("cast_unavailable", "Google Cast is unavailable on this device.", null)
        }
    }

    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("cast_closed", "The Cast controller is closed.", null)
            return
        }
        try {
            if (call.method == "disconnect") {
                disconnect(call, result)
                return
            }
            initialize()
            when (call.method) {
                "connect" -> {
                    val owner = call.argument<String>("owner")
                    if (owner.isNullOrBlank()) {
                        result.error("cast_owner_required", "A Cast controller is required.", null)
                    } else if (pendingConnect != null || pendingDisconnect != null) {
                        result.error("cast_busy", "The Cast chooser is already open.", null)
                    } else if (session?.isConnected == true) {
                        claimOwner(owner)
                        result.success(state())
                    } else {
                        pendingConnect = result
                        pendingConnectOwner = owner
                        claimOwner(owner)
                        handler.postDelayed(connectTimeout, 55_000)
                        showChooser()
                    }
                }
                "showChooser" -> {
                    if (!ownsSession(call)) {
                        result.error("cast_stale_session", "Cast control moved to another target.", null)
                    } else {
                        showChooser()
                        result.success(state())
                    }
                }
                "load", "play", "pause", "seek" -> command(call, result)
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            if (pendingConnect === result) {
                failConnect("cast_unavailable", "Google Cast is unavailable. Check Google Play services.")
            } else {
                result.error("cast_unavailable", "Google Cast is unavailable. Check Google Play services.", null)
            }
        }
    }

    private fun showChooser() {
        // Use Google's configured MediaRouter UI with a compatible dialog theme.
        val themed = ContextThemeWrapper(activity, androidx.appcompat.R.style.Theme_AppCompat_DayNight)
        val button = MediaRouteButton(themed)
        activity.supportFragmentManager.setFragmentResultListener("meowwatch_cast_cancelled", activity) { _, _ ->
            failConnect("cast_cancelled", "Cast connection cancelled.")
        }
        CastButtonFactory.setUpMediaRouteButton(activity, button)
        val manager = activity.supportFragmentManager
        if (manager.findFragmentByTag("meowwatch_cast_dialog") != null) {
            throw IllegalStateException("Cast chooser already open")
        }
        // Flutter renders the action. Its native dialog uses the selector supplied
        // by CastButtonFactory; MediaRouteButton.showDialog requires an attached View.
        if (session?.isConnected == true) {
            CastControllerDialogFragment().apply {
                routeSelector = button.routeSelector
            }.show(manager, "meowwatch_cast_dialog")
        } else {
            CastChooserDialogFragment().apply {
                routeSelector = button.routeSelector
                chooser = this
            }.show(manager, "meowwatch_cast_dialog")
        }
    }

    private fun starting(value: CastSession) {
        if (session !== value) {
            unbind()
            failCommands()
            pendingDisconnect?.error("cast_stale_session", "The Cast session changed.", null)
            pendingDisconnect = null
            handler.removeCallbacks(disconnectTimeout)
            session = value
            generation++
            currentOwner = pendingConnectOwner
        }
        connection = "connecting"
        emit()
    }

    private fun connected(value: CastSession) {
        if (session !== value) starting(value)
        connection = "connected"
        unbind()
        val remote = value.remoteMediaClient
        client = remote
        val epoch = generation
        if (remote != null) {
            callback = object : RemoteMediaClient.Callback() {
                override fun onStatusUpdated() { if (epoch == generation && client === remote) emit() }
                override fun onMetadataUpdated() { if (epoch == generation && client === remote) emit() }
            }.also { remote.registerCallback(it) }
            progress = RemoteMediaClient.ProgressListener { _, _ ->
                if (epoch == generation && client === remote) emit()
            }.also { remote.addProgressListener(it, 500) }
        }
        emit()
        val result = pendingConnect
        pendingConnect = null
        pendingConnectOwner = null
        handler.removeCallbacks(connectTimeout)
        result?.success(state())
    }

    private fun lost(value: CastSession, reason: String) {
        if (session !== value) return
        unbind()
        failCommands()
        connection = reason
        failConnect("cast_disconnected", "The TV disconnected. Try again.")
        emit()
    }

    private fun unbind() {
        callback?.let { client?.unregisterCallback(it) }
        progress?.let { client?.removeProgressListener(it) }
        callback = null
        progress = null
        client = null
    }

    private fun command(call: MethodCall, result: MethodChannel.Result) {
        val epoch = (call.argument<Number>("generation"))?.toLong()
        val owner = call.argument<String>("owner")
        val remote = client
        if (!ownsSession(call) || connection != "connected" || remote == null) {
            result.error("cast_disconnected", "Reconnect to the TV before controlling playback.", null)
            return
        }
        val token = call.argument<String>("mediaToken")
        if (call.method != "load" && (token == null || remote.mediaInfo?.customData?.optString("meowwatchLoadId") != token)) {
            result.error("cast_media_changed", "The video on the TV changed. Open your video again.", null)
            return
        }
        val request: PendingResult<RemoteMediaClient.MediaChannelResult> = when (call.method) {
            "load" -> {
                val url = call.argument<String>("url")
                if (!allowedUrl(url) || token.isNullOrBlank() || call.argument<String>("contentType") != "video/mp4") {
                    result.error("cast_media_unsupported", "Choose a public HTTPS MP4 link without URL parameters.", null)
                    return
                }
                val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
                    putString(MediaMetadata.KEY_TITLE, "MeowWatch video")
                }
                val media = MediaInfo.Builder(url!!)
                    .setContentType("video/mp4")
                    .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                    .setMetadata(metadata)
                    .setCustomData(JSONObject().put("meowwatchLoadId", token))
                    .build()
                remote.load(MediaLoadRequestData.Builder()
                    .setMediaInfo(media)
                    .setAutoplay(false)
                    .setCurrentTime((call.argument<Number>("positionMs")?.toLong() ?: 0).coerceAtLeast(0))
                    .build())
            }
            "play" -> remote.play()
            "pause" -> remote.pause()
            else -> remote.seek(MediaSeekOptions.Builder()
                .setPosition((call.argument<Number>("positionMs")?.toLong() ?: 0).coerceAtLeast(0))
                .build())
        }
        pendingCommands.add(result)
        request.setResultCallback({ response ->
            if (!pendingCommands.remove(result)) return@setResultCallback
            if (closed || generation != epoch || currentOwner != owner || client !== remote || connection != "connected") {
                result.error("cast_stale_session", "The Cast session changed. Try again.", null)
            } else if (!response.status.isSuccess) {
                result.error("cast_command_failed", "The TV could not complete the playback command. Try again.", null)
            } else if (call.method != "load" && remote.mediaInfo?.customData?.optString("meowwatchLoadId") != token) {
                result.error("cast_media_changed", "The video on the TV changed. Open your video again.", null)
            } else {
                emit()
                result.success(state())
            }
        }, 25, TimeUnit.SECONDS)
    }

    private fun disconnect(call: MethodCall, result: MethodChannel.Result) {
        // A stale Flutter target must never stop a replacement receiver session.
        val owner = call.argument<String>("owner")
        val ownsPending = !owner.isNullOrBlank() && pendingConnect != null && owner == pendingConnectOwner
        if (ownsSession(call) || ownsPending) {
            if (pendingDisconnect != null) {
                result.error("cast_busy", "The TV is already disconnecting.", null)
                return
            }
            failConnect("cast_cancelled", "Cast connection cancelled.")
            currentOwner = null
            chooser?.dismissAllowingStateLoss()
            unbind()
            failCommands()
            connection = "disconnected"
            if (session != null && context?.sessionManager?.currentCastSession === session) {
                pendingDisconnect = result
                handler.postDelayed(disconnectTimeout, 10_000)
                context?.sessionManager?.endCurrentSession(true)
                emit()
                return
            }
            context?.sessionManager?.endCurrentSession(true)
            emit()
        }
        result.success(state())
    }

    private fun state(): Map<String, Any?> {
        val media = client?.mediaStatus
        val player = when (media?.playerState) {
            MediaStatus.PLAYER_STATE_PLAYING -> "playing"
            MediaStatus.PLAYER_STATE_PAUSED -> "paused"
            MediaStatus.PLAYER_STATE_BUFFERING -> "buffering"
            MediaStatus.PLAYER_STATE_LOADING -> "loading"
            MediaStatus.PLAYER_STATE_IDLE -> when (media.idleReason) {
                MediaStatus.IDLE_REASON_FINISHED -> "ended"
                MediaStatus.IDLE_REASON_ERROR -> "failed"
                MediaStatus.IDLE_REASON_CANCELED, MediaStatus.IDLE_REASON_INTERRUPTED -> "failed"
                else -> "idle"
            }
            else -> "idle"
        }
        return mapOf(
            "generation" to generation,
            "owner" to currentOwner,
            "revision" to ++revision,
            "session" to connection,
            "receiverName" to (session?.castDevice?.friendlyName ?: "TV"),
            "player" to player,
            "mediaToken" to client?.mediaInfo?.customData?.optString("meowwatchLoadId"),
            "positionMs" to (client?.approximateStreamPosition ?: 0L),
            "durationMs" to (client?.streamDuration ?: 0L),
        )
    }

    private fun emit() { if (!closed) sink?.success(state()) }

    private fun failConnect(code: String, message: String) {
        val result = pendingConnect
        if (pendingConnectOwner != null && currentOwner == pendingConnectOwner) currentOwner = null
        pendingConnect = null
        pendingConnectOwner = null
        handler.removeCallbacks(connectTimeout)
        result?.error(code, message, null)
    }

    private fun ownsSession(call: MethodCall): Boolean {
        val owner = call.argument<String>("owner")
        return !owner.isNullOrBlank() && owner == currentOwner &&
            call.argument<Number>("generation")?.toLong() == generation
    }

    private fun claimOwner(owner: String) {
        if (currentOwner != owner) {
            failCommands()
            currentOwner = owner
            emit()
        }
    }

    private fun failCommands() {
        val commands = pendingCommands.toList()
        pendingCommands.clear()
        commands.forEach { it.error("cast_stale_session", "The Cast session changed. Try again.", null) }
    }

    fun dispose() {
        closed = true
        failConnect("cast_closed", "The Cast controller closed.")
        failCommands()
        pendingDisconnect?.error("cast_closed", "The Cast controller closed.", null)
        pendingDisconnect = null
        handler.removeCallbacks(disconnectTimeout)
        unbind()
        context?.sessionManager?.removeSessionManagerListener(listener, CastSession::class.java)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        activity.supportFragmentManager.clearFragmentResultListener("meowwatch_cast_cancelled")
        sink = null
        // Activity recreation must not stop receiver playback or the notification.
    }

    private fun allowedUrl(value: String?): Boolean = try {
        val uri = URI(value ?: "")
        val host = uri.host?.lowercase()?.removeSuffix(".") ?: ""
        uri.scheme == "https" && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
            uri.path.lowercase().endsWith(".mp4") && host.contains('.') && !host.contains(':') &&
            !host.matches(Regex("[0-9.]+")) &&
            listOf(".local", ".localhost", ".internal", ".home.arpa").none { host.endsWith(it) }
    } catch (_: Exception) { false }
}
