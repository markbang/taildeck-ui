package top.bangwu.taildeck_ui

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
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
        // The launch link's query, read once by the Dart preview parameters.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taildeck/link")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialQuery" -> result.success(intent?.data?.query)
                    else -> result.notImplemented()
                }
            }
        // The terminal hides its extra key row behind a physical keyboard.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taildeck/keyboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "attached" -> result.success(
                        resources.configuration.keyboard != Configuration.KEYBOARD_NOKEYS
                    )
                    else -> result.notImplemented()
                }
            }
        // As in the Kotlin app: every WebView goes through the gateway, which is
        // also a forward proxy, so pages load from their tailnet URL and
        // absolute links to tailnet hosts (a NAS's raw file URLs) resolve.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taildeck/webview")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "proxy" -> {
                        val port = call.argument<Int>("port") ?: 0
                        if (port <= 0 || !WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                            result.success(false)
                        } else {
                            // This WebView plays HLS through the platform MediaPlayer,
                            // which fetches with the app's Java HTTP stack, not the
                            // WebView's: point that stack at the gateway as well.
                            System.setProperty("http.proxyHost", "127.0.0.1")
                            System.setProperty("http.proxyPort", port.toString())
                            val config = ProxyConfig.Builder().addProxyRule("127.0.0.1:$port").build()
                            ProxyController.getInstance()
                                .setProxyOverride(config, { it.run() }) { result.success(true) }
                        }
                    }
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
