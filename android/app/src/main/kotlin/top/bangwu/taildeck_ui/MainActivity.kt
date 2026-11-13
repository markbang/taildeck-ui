package top.bangwu.taildeck_ui

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import top.bangwu.taildeck.PlatformBridge

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Flutter backend starts the Go node with platform "host" only
        // when this returns true.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taildeck/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> result.success(PlatformBridge.register(this))
                    else -> result.notImplemented()
                }
            }
    }
}
