package com.tanglex.chat

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tanglex/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readFiles" -> result.success(readClipboardFiles())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Clipboard media arrives as `content://` URIs the Dart side cannot open,
     * so every item is copied into the cache first; that is what the desktop
     * clients get for free from local file paths.
     */
    private fun readClipboardFiles(): Map<String, Any?> {
        val paths = mutableListOf<String>()
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        if (clip != null) {
            val dir = File(cacheDir, "clipboard").apply { mkdirs() }
            for (index in 0 until clip.itemCount) {
                val uri: Uri = clip.getItemAt(index).uri ?: continue
                val mime = contentResolver.getType(uri).orEmpty()
                val extension = MimeTypeMap.getSingleton()
                    .getExtensionFromMimeType(mime) ?: "bin"
                val target = File(
                    dir,
                    "paste-${System.currentTimeMillis()}-$index.$extension",
                )
                try {
                    val input = contentResolver.openInputStream(uri) ?: continue
                    input.use { source ->
                        target.outputStream().use { sink -> source.copyTo(sink) }
                    }
                } catch (e: Exception) {
                    continue
                }
                paths.add(target.absolutePath)
            }
        }
        return mapOf("paths" to paths, "imagePath" to null)
    }
}
