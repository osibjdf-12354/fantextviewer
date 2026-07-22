package com.songs.geulbom

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
}
