package app.family.family_utility_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var linkChannel: MethodChannel? = null
    private var pendingLink: String? = null

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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent) ?: return
        linkChannel?.invokeMethod("link", text)
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
}
