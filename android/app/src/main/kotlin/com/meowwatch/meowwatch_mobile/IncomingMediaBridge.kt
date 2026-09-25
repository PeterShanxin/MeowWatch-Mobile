package com.meowwatch.meowwatch_mobile

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Process
import androidx.core.content.IntentCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import java.util.ArrayDeque
import java.util.UUID

/** Intake only: never reads video bytes, fetches a network URL, or starts a player. */
class IncomingMediaBridge(private val context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "com.meowwatch.mobile/incoming-media")
    private val events = EventChannel(messenger, "com.meowwatch.mobile/incoming-media/events")
    private var eventSink: EventChannel.EventSink? = null

    // Survives activity recreation; bounded and deliberately not written to disk.
    // MainActivity's saved-instance marker prevents replaying its original intent.
    private object Inbox {
        val queue = ArrayDeque<Map<String, Any?>>()
        const val CAPACITY = 8
    }

    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method == "drain") {
                val pending = Inbox.queue.toList()
                Inbox.queue.clear()
                result.success(pending)
            } else result.notImplemented()
        }
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        if (Inbox.queue.isNotEmpty()) sink.success(null)
    }

    override fun onCancel(arguments: Any?) { eventSink = null }

    fun accept(intent: Intent?, overflowedBeforeReady: Boolean = false): Boolean {
        if (intent == null) return false
        // meowwatch://join VIEW belongs exclusively to app_links.
        if (intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "meowwatch") return false
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_VIEW) return false
        val payload = try {
            val mime = intent.type
            when {
                intent.action == Intent.ACTION_SEND && mime == "text/plain" -> {
                    val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
                    if (text == null || text.length > MAX_URI_LENGTH) error("invalid_payload")
                    else fromUri(text.toString().trim(), null, intent)
                }
                intent.action == Intent.ACTION_SEND && isVideoMime(mime) -> {
                    val uri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                        ?: intent.clipData?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.uri
                    if (uri == null) error("invalid_payload") else fromUri(uri.toString(), mime, intent)
                }
                intent.action == Intent.ACTION_VIEW -> {
                    val uri = intent.data
                    if (uri == null) error("invalid_payload") else fromUri(uri.toString(), mime, intent)
                }
                else -> error("unsupported_media")
            }
        } catch (_: Exception) {
            error("invalid_payload")
        }
        val full = Inbox.queue.size >= Inbox.CAPACITY
        val overflow = full || overflowedBeforeReady
        if (full) Inbox.queue.removeFirst()
        Inbox.queue.addLast(payload + mapOf("id" to UUID.randomUUID().toString(), "overflow" to overflow))
        eventSink?.success(null)
        return true
    }

    private fun fromUri(value: String, mime: String?, intent: Intent): Map<String, Any?> {
        if (value.isEmpty() || value.length > MAX_URI_LENGTH || value.any { it <= ' ' || it == '\u007f' }) {
            return error("invalid_payload")
        }
        val parsed = try { URI(value) } catch (_: Exception) { return error("invalid_payload") }
        if (parsed.rawUserInfo != null) return error("invalid_payload")
        val uri = Uri.parse(value)
        return when (parsed.scheme) {
            "meowwatch" -> if (intent.action == Intent.ACTION_SEND && parsed.host == "join") {
                mapOf("kind" to "invite", "uri" to value)
            } else error("unsupported_media")
            "http", "https" -> {
                if (parsed.host.isNullOrEmpty()) return error("invalid_payload")
                val extension = parsed.path?.substringAfterLast('.', "")?.lowercase()
                if (!isVideoMime(mime) && extension !in VIDEO_EXTENSIONS) return error("unsupported_media")
                mapOf("kind" to "media", "uri" to value, "mimeType" to mime, "durableAccess" to false)
            }
            "content" -> {
                if (parsed.rawAuthority.isNullOrEmpty() || !isVideoMime(mime)) return error("unsupported_media")
                val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
                if (context.checkUriPermission(uri, Process.myPid(), Process.myUid(), read) != PackageManager.PERMISSION_GRANTED) {
                    return error("permission_denied")
                }
                val resolver = context.contentResolver
                fun hasPersistedRead() = resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
                var durable = hasPersistedRead()
                val persistable = Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                if (!durable && intent.flags and read != 0 && intent.flags and persistable != 0) {
                    try {
                        resolver.takePersistableUriPermission(uri, read)
                        durable = hasPersistedRead()
                    } catch (_: SecurityException) {
                        // The actual read grant remains usable, but is not durable.
                    }
                }
                mapOf("kind" to "media", "uri" to value, "mimeType" to mime,
                    "readAccess" to true, "durableAccess" to durable)
            }
            else -> error("unsupported_media")
        }
    }

    private fun isVideoMime(value: String?) = value != null && value.length <= 100 &&
        value.matches(Regex("video/[a-zA-Z0-9.+*_-]+"))

    private fun error(code: String): Map<String, Any?> = mapOf("kind" to "error", "errorCode" to code)

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
    }

    companion object {
        private const val MAX_URI_LENGTH = 4096
        private val VIDEO_EXTENSIONS = setOf("mp4", "m4v", "mov", "webm", "mkv", "3gp", "m3u8", "mpd")
    }
}
