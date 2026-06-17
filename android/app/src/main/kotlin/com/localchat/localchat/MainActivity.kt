package com.localchat.localchat

import android.content.ContentValues
import android.content.Context
import android.content.ClipboardManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

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
                    val subpath = call.argument<String>("subpath") ?: ""
                    val saved = saveFileToDownloads(sourcePath, fileName, mimeType, subpath)
                    result.success(saved)
                } catch (error: Throwable) {
                    result.error("save_failed", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "localchat/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "getFiles") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(readClipboardFiles())
                } catch (error: Throwable) {
                    result.error("clipboard_failed", error.message, null)
                }
            }
    }

    private fun saveFileToDownloads(
        sourcePath: String,
        fileName: String,
        mimeType: String,
        subpath: String,
    ): Map<String, String?> {
        val source = File(sourcePath)
        require(source.exists()) { "Source file does not exist" }
        val safeName = fileName.replace(Regex("""[\\/:*?"<>|]"""), "_")
        // 清洗子路径中的非法字符，保留目录层级。
        val cleanedSubpath = subpath.split("/")
            .map { it.replace(Regex("""[\\/:*?"<>|]"""), "_").trim() }
            .filter { it.isNotEmpty() && it != "." && it != ".." }
            .joinToString("/")
        val relativeBase = "${Environment.DIRECTORY_DOWNLOADS}/LocalChat" +
            (if (cleanedSubpath.isNotEmpty()) "/$cleanedSubpath" else "")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, relativeBase)
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
                "path" to "$relativeBase/$safeName",
                "uri" to uri.toString(),
            )
        }

        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "LocalChat/$cleanedSubpath",
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

    private fun readClipboardFiles(): List<String> {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return emptyList()
        val files = mutableListOf<String>()
        for (index in 0 until clip.itemCount) {
            val uri = clip.getItemAt(index).uri ?: continue
            files.add(copyClipboardUri(uri))
        }
        return files
    }

    private fun copyClipboardUri(uri: Uri): String {
        val resolver = applicationContext.contentResolver
        val mimeType = resolver.getType(uri)
        val fileName = clipboardFileName(uri, mimeType)
        val dir = File(cacheDir, "clipboard")
        dir.mkdirs()
        val target = uniqueFile(dir, fileName)
        resolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Unable to open clipboard item")
        return target.absolutePath
    }

    private fun clipboardFileName(uri: Uri, mimeType: String?): String {
        val displayName = queryDisplayName(uri)
        if (!displayName.isNullOrBlank()) {
            return displayName.replace(Regex("""[\\/:*?"<>|]"""), "_")
        }
        val extension = if (mimeType == null) {
            "bin"
        } else {
            MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "bin"
        }
        return "clipboard-${System.currentTimeMillis()}.$extension"
    }

    private fun queryDisplayName(uri: Uri): String? {
        val resolver = applicationContext.contentResolver
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return null
    }
}
