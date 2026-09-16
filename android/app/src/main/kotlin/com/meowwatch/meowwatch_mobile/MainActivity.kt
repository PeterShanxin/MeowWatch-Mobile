package com.meowwatch.meowwatch_mobile

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingPicker: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.meowwatch.mobile/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickVideo" -> {
                        if (pendingPicker != null) {
                            result.error("picker_busy", "A file picker is already open.", null)
                        } else {
                            pendingPicker = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "video/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }
                            try {
                                startActivityForResult(intent, 7101)
                            } catch (error: Exception) {
                                pendingPicker = null
                                result.error("picker_unavailable", "No document picker is available.", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Activity result bridge retained for Flutter's embedding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7101) return
        val result = pendingPicker ?: return
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            var title = "Selected video"
            var size: Long? = null
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    title = cursor.getString(0) ?: title
                    if (!cursor.isNull(1)) size = cursor.getLong(1)
                }
            }
            result.success(mapOf("uri" to uri.toString(), "title" to title, "sizeBytes" to size))
        } catch (error: Exception) {
            result.error("file_access", "Could not keep access to this video. Choose a file from device storage.", null)
        }
    }
}
