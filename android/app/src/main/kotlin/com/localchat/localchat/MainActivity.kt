package com.localchat.localchat

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "localchat/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val sourcePath = call.argument<String>("sourcePath")
                        ?: throw IllegalArgumentException("sourcePath is required")
                    val fileName = call.argument<String>("fileName") ?: File(sourcePath).name
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val saved = saveFileToDownloads(sourcePath, fileName, mimeType)
                    result.success(saved)
                } catch (error: Throwable) {
                    result.error("save_failed", error.message, null)
                }
            }
    }

    private fun saveFileToDownloads(
        sourcePath: String,
        fileName: String,
        mimeType: String,
    ): Map<String, String?> {
        val source = File(sourcePath)
        require(source.exists()) { "Source file does not exist" }
        val safeName = fileName.replace(Regex("""[\\/:*?"<>|]"""), "_")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/LocalChat")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create Downloads item")
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Unable to open Downloads item")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return mapOf(
                "path" to "Downloads/LocalChat/$safeName",
                "uri" to uri.toString(),
            )
        }

        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "LocalChat",
        )
        dir.mkdirs()
        val target = uniqueFile(dir, safeName)
        source.copyTo(target, overwrite = false)
        return mapOf("path" to target.absolutePath, "uri" to null)
    }

    private fun uniqueFile(dir: File, fileName: String): File {
        var candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var index = 1
        while (candidate.exists()) {
            candidate = File(dir, "$stem ($index)$extension")
            index++
        }
        return candidate
    }
}
