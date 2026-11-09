package app.family.family_utility_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var linkChannel: MethodChannel? = null
    private var pendingLink: String? = null
    private var filesChannel: MethodChannel? = null
    private var pendingFiles: List<String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 123 Video from a link: text shared into the app goes to Dart.
        pendingLink = sharedText(intent)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.family/shared_link")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "initialLink") {
                result.success(pendingLink)
                pendingLink = null
            } else {
                result.notImplemented()
            }
        }
        linkChannel = channel

        // 025 HEIC to JPG: pictures shared from Photos/Gallery, in order.
        pendingFiles = sharedFiles(intent)
        val files = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.family/shared_files")
        files.setMethodCallHandler { call, result ->
            if (call.method == "initialFiles") {
                result.success(pendingFiles)
                pendingFiles = null
            } else {
                result.notImplemented()
            }
        }
        filesChannel = files
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent)
        if (text != null) {
            linkChannel?.invokeMethod("link", text)
            return
        }
        val paths = sharedFiles(intent) ?: return
        filesChannel?.invokeMethod("files", paths)
    }

    private fun sharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) {
            return null
        }
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) {
            return null
        }
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }

    @Suppress("DEPRECATION")
    private fun streamUris(intent: Intent): List<Uri> {
        val out = ArrayList<Uri>()
        if (intent.action == Intent.ACTION_SEND) {
            val one: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (one != null) {
                out.add(one)
            }
        } else if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val many: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (many != null) {
                out.addAll(many)
            }
        }
        return out
    }

    /// Copies shared pictures into the cache (one folder per picture so the
    /// original names survive) and returns their paths in shared order.
    private fun sharedFiles(intent: Intent?): List<String>? {
        if (intent == null) {
            return null
        }
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }
        val type = intent.type ?: return null
        if (!type.startsWith("image/")) {
            return null
        }
        val uris = streamUris(intent)
        if (uris.isEmpty()) {
            return null
        }
        val batch = File(cacheDir, "shared_in/" + System.currentTimeMillis())
        val out = ArrayList<String>()
        for ((i, uri) in uris.withIndex()) {
            try {
                val dir = File(batch, i.toString())
                dir.mkdirs()
                val name = (displayName(uri) ?: "photo_$i").replace('/', '_')
                val target = File(dir, name)
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                if (target.exists()) {
                    out.add(target.absolutePath)
                }
            } catch (e: Exception) {
                // An unreadable picture is skipped; the rest still arrive.
            }
        }
        return out
    }

    private fun displayName(uri: Uri): String? {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        return c.getString(idx)
                    }
                }
            }
        } catch (e: Exception) {
            // Fall back to the last path segment.
        }
        return uri.lastPathSegment
    }
}
