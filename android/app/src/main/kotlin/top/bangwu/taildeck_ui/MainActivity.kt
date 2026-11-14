package top.bangwu.taildeck_ui

import android.content.Intent
import android.os.Build
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
        // The Flutter backend starts this around its own node lifecycle.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taildeck/service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, TailnetService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, TailnetService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
