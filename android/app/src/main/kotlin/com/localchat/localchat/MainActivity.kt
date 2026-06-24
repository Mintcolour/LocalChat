package com.localchat.localchat

import android.content.ContentValues
import android.content.Context
import android.content.ClipboardManager
import android.content.Intent
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
                try {
                    when (call.method) {
                        "saveFile" -> {
                            val sourcePath = call.argument<String>("sourcePath")
                                ?: throw IllegalArgumentException("sourcePath is required")
                            val fileName = call.argument<String>("fileName") ?: File(sourcePath).name
                            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                            val subpath = call.argument<String>("subpath") ?: ""
                            result.success(saveFileToDownloads(sourcePath, fileName, mimeType, subpath))
                        }
                        "renameFile" -> {
                            val currentPath = call.argument<String>("currentPath")
                                ?: throw IllegalArgumentException("currentPath is required")
                            val currentUri = call.argument<String>("currentUri")
                            val fileName = call.argument<String>("fileName")
                                ?: throw IllegalArgumentException("fileName is required")
                            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                            val subpath = call.argument<String>("subpath") ?: ""
                            result.success(
                                renameDownloadedFile(
                                    currentPath,
                                    currentUri,
                                    fileName,
                                    mimeType,
                                    subpath,
                                ),
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("downloads_failed", error.message, null)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "localchat/keep_alive")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            startKeepAliveService()
                            result.success(true)
                        }
                        "stop" -> {
                            stopKeepAliveService()
                            result.success(null)
                        }
                        "isRunning" -> result.success(LocalChatForegroundService.isRunning)
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("keep_alive_failed", error.message, null)
                }
            }
    }

    private fun startKeepAliveService() {
        val intent = Intent(this, LocalChatForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopKeepAliveService() {
        stopService(Intent(this, LocalChatForegroundService::class.java))
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
            val mediaStorePath = "$relativeBase/"
            val uniqueName = uniqueMediaStoreName(null, mediaStorePath, safeName)
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, uniqueName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, mediaStorePath)
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
                "fileName" to uniqueName,
                "path" to "$relativeBase/$uniqueName",
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
        return mapOf("fileName" to target.name, "path" to target.absolutePath, "uri" to null)
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

    private fun renameDownloadedFile(
        currentPath: String,
        currentUri: String?,
        requestedName: String,
        mimeType: String,
        subpath: String,
    ): Map<String, String?> {
        val safeName = requestedName.replace(Regex("""[\\/:*?"<>|]"""), "_")
        val cleanedSubpath = cleanSubpath(subpath)
        val relativeBase = "${Environment.DIRECTORY_DOWNLOADS}/LocalChat" +
            (if (cleanedSubpath.isNotEmpty()) "/$cleanedSubpath" else "")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !currentUri.isNullOrBlank()) {
            val uri = Uri.parse(currentUri)
            val mediaStorePath = "$relativeBase/"
            val uniqueName = uniqueMediaStoreName(uri, mediaStorePath, safeName)
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, uniqueName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, mediaStorePath)
            }
            val updated = applicationContext.contentResolver.update(uri, values, null, null)
            check(updated > 0) { "Unable to rename Downloads item" }
            return mapOf(
                "fileName" to uniqueName,
                "path" to "$relativeBase/$uniqueName",
                "uri" to uri.toString(),
            )
        }

        val source = File(currentPath)
        require(source.exists()) { "Saved file does not exist" }
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "LocalChat/$cleanedSubpath",
        )
        dir.mkdirs()
        val target = if (source.parentFile == dir && source.name == safeName) {
            source
        } else {
            uniqueFile(dir, safeName)
        }
        if (target != source) {
            if (!source.renameTo(target)) {
                source.copyTo(target, overwrite = false)
                check(source.delete()) { "Unable to remove old Downloads item" }
            }
        }
        return mapOf(
            "fileName" to target.name,
            "path" to target.absolutePath,
            "uri" to null,
        )
    }

    private fun cleanSubpath(subpath: String): String = subpath.split('/', '\\')
        .map { it.replace(Regex("""[\\/:*?"<>|]"""), "_").trim() }
        .filter { it.isNotEmpty() && it != "." && it != ".." }
        .joinToString("/")

    private fun uniqueMediaStoreName(
        currentUri: Uri?,
        relativePath: String,
        requestedName: String,
    ): String {
        val currentId = currentUri?.lastPathSegment
        val dot = requestedName.lastIndexOf('.')
        val stem = if (dot > 0) requestedName.substring(0, dot) else requestedName
        val extension = if (dot > 0) requestedName.substring(dot) else ""
        var candidate = requestedName
        var index = 1
        while (mediaStoreNameExists(relativePath, candidate, currentId)) {
            candidate = "$stem ($index)$extension"
            index++
        }
        return candidate
    }

    private fun mediaStoreNameExists(
        relativePath: String,
        displayName: String,
        currentId: String?,
    ): Boolean {
        val projection = arrayOf(MediaStore.Downloads._ID)
        val selection = "${MediaStore.Downloads.RELATIVE_PATH}=? AND " +
            "${MediaStore.Downloads.DISPLAY_NAME}=?"
        val args = arrayOf(relativePath, displayName)
        applicationContext.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            args,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getLong(0).toString() != currentId) return true
            }
        }
        return false
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
