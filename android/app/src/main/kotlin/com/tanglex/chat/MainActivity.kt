package com.tanglex.chat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Remove plugins that cause excessive attach/detach log spam
        // but are not actually used by the app.
        flutterEngine.plugins.remove("dev.britannio.archive.ArchivePlugin")
    }
}
