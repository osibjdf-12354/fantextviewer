package com.songs.geulbom

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.charset.Charset
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val decoder = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.songs.geulbom/text-file",
        ).setMethodCallHandler { call, result ->
            if (call.method != "decode") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val encoding = call.argument<String>("encoding")
            if (path == null || encoding == null) {
                result.error("invalid_argument", "path and encoding are required", null)
                return@setMethodCallHandler
            }
            decoder.execute {
                try {
                    val text =
                        File(path).bufferedReader(Charset.forName(encoding)).use { it.readText() }
                    runOnUiThread { result.success(text) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.error("decode_failed", error.message, error.toString())
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val display = window.decorView.display ?: return
        val currentMode = display.mode
        val maximumRefreshRate = display.supportedModes
            .asSequence()
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxOfOrNull { it.refreshRate }
            ?: return
        window.attributes = window.attributes.apply {
            preferredRefreshRate = maximumRefreshRate
        }
    }

    override fun onDestroy() {
        decoder.shutdown()
        super.onDestroy()
    }
}
