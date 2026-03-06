package com.xiaoyanquan.xiaoyanquan

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.charset.Charset
import java.util.UUID

class LivePhotoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null

    private var isMultiPick = false

    companion object {
        private const val REQUEST_PICK_LIVE = 9908
        private const val REQUEST_PICK_LIVE_MULTI = 9909
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.xiaoyanquan/live_photo")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveLivePhoto" -> {
                // Android 不支持保存为 iOS Live Photo 结构
                result.error("UNSUPPORTED", "Live Photo save is not supported on Android", null)
            }
            "requestPermission" -> {
                result.success(true)
            }
            "pickLiveForUpload" -> pickLiveForUpload(result)
            "pickMultipleLiveForUpload" -> pickMultipleLiveForUpload(result)
            else -> result.notImplemented()
        }
    }

    private fun pickLiveForUpload(result: MethodChannel.Result) {
        launchPicker(result, multi = false)
    }

    private fun pickMultipleLiveForUpload(result: MethodChannel.Result) {
        launchPicker(result, multi = true)
    }

    private fun launchPicker(result: MethodChannel.Result, multi: Boolean) {
        val hostActivity = activity
        if (hostActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not attached", null)
            return
        }
        if (pendingResult != null) {
            result.error("BUSY", "Live picker is busy", null)
            return
        }

        pendingResult = result
        isMultiPick = multi
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            if (multi) putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        hostActivity.startActivityForResult(
            intent,
            if (multi) REQUEST_PICK_LIVE_MULTI else REQUEST_PICK_LIVE,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_LIVE && requestCode != REQUEST_PICK_LIVE_MULTI) return false
        val result = pendingResult
        val multi = isMultiPick
        pendingResult = null
        isMultiPick = false

        if (result == null) return true
        if (resultCode != Activity.RESULT_OK) {
            result.success(if (multi) emptyList<Map<String, Any>>() else null)
            return true
        }

        val hostActivity = activity
        if (hostActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not attached", null)
            return true
        }

        // 收集所有 URI
        val uris = mutableListOf<Uri>()
        val clipData = data?.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                clipData.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        } else {
            data?.data?.let { uris.add(it) }
        }

        if (uris.isEmpty()) {
            result.success(if (multi) emptyList<Map<String, Any>>() else null)
            return true
        }

        try {
            val payloads = mutableListOf<Map<String, Any>>()
            for (uri in uris) {
                val payload = processMotionPhotoUri(hostActivity, uri)
                if (payload != null) payloads.add(payload)
            }

            if (!multi) {
                if (payloads.isEmpty()) {
                    result.error("NO_MOTION_VIDEO", "未检测到 Live/Motion 的动态视频片段，请改用手动选择静态图+视频", null)
                } else {
                    result.success(payloads.first())
                }
            } else {
                result.success(payloads)
            }
        } catch (e: Exception) {
            result.error("PICK_FAILED", "Live pick failed: ${e.message}", null)
        }
        return true
    }

    private fun processMotionPhotoUri(hostActivity: Activity, uri: Uri): Map<String, Any>? {
        val bytes = readAllBytes(hostActivity.contentResolver.openInputStream(uri))
        if (bytes.isEmpty()) return null

        val imageExt = inferImageExtension(hostActivity, uri)
        val imageFile = File(hostActivity.cacheDir, "live_img_${UUID.randomUUID()}.$imageExt")
        writeBytes(imageFile, bytes)

        val videoBytes = extractMotionVideoBytes(bytes) ?: return null
        val videoFile = File(hostActivity.cacheDir, "live_vid_${UUID.randomUUID()}.mp4")
        writeBytes(videoFile, videoBytes)

        return mapOf(
            "image_path" to imageFile.absolutePath,
            "video_path" to videoFile.absolutePath,
            "image_name" to imageFile.name,
            "video_name" to videoFile.name,
            "source" to "android_motion_photo",
        )
    }

    private fun readAllBytes(inputStream: InputStream?): ByteArray {
        if (inputStream == null) return ByteArray(0)
        inputStream.use { stream ->
            return stream.readBytes()
        }
    }

    private fun writeBytes(file: File, bytes: ByteArray) {
        FileOutputStream(file).use { out ->
            out.write(bytes)
            out.flush()
        }
    }

    private fun inferImageExtension(activity: Activity, uri: Uri): String {
        val mime = activity.contentResolver.getType(uri).orEmpty().lowercase()
        if (mime.contains("heic") || mime.contains("heif")) return "heic"
        val fromMime = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        if (!fromMime.isNullOrBlank()) return fromMime
        return "jpg"
    }

    private fun extractMotionVideoBytes(bytes: ByteArray): ByteArray? {
        val fromOffset = extractByMicroVideoOffset(bytes)
        if (fromOffset != null) return fromOffset
        return extractByFtypFallback(bytes)
    }

    private fun extractByMicroVideoOffset(bytes: ByteArray): ByteArray? {
        val text = bytes.toString(Charset.forName("ISO-8859-1"))
        val offset = parseMicroVideoOffset(text) ?: return null
        if (offset <= 0 || offset >= bytes.size) return null
        val start = bytes.size - offset
        if (!looksLikeMp4(bytes, start)) return null
        return bytes.copyOfRange(start, bytes.size)
    }

    private fun parseMicroVideoOffset(text: String): Int? {
        val patterns = listOf(
            "MicroVideoOffset=\"",
            "MicroVideoOffset=",
            "GCamera:MicroVideoOffset=\"",
            "Camera:MicroVideoOffset=\"",
        )
        for (pattern in patterns) {
            val idx = text.indexOf(pattern)
            if (idx < 0) continue
            var pos = idx + pattern.length
            val builder = StringBuilder()
            while (pos < text.length) {
                val ch = text[pos]
                if (ch.isDigit()) {
                    builder.append(ch)
                } else if (builder.isNotEmpty()) {
                    break
                }
                pos += 1
            }
            if (builder.isNotEmpty()) {
                return builder.toString().toIntOrNull()
            }
        }
        return null
    }

    private fun extractByFtypFallback(bytes: ByteArray): ByteArray? {
        val marker = byteArrayOf('f'.code.toByte(), 't'.code.toByte(), 'y'.code.toByte(), 'p'.code.toByte())
        var idx = lastIndexOf(bytes, marker)
        while (idx >= 4) {
            val start = idx - 4
            if (looksLikeMp4(bytes, start)) {
                return bytes.copyOfRange(start, bytes.size)
            }
            idx = lastIndexOf(bytes, marker, start - 1)
        }
        return null
    }

    private fun lastIndexOf(source: ByteArray, target: ByteArray, fromIndex: Int = source.size - target.size): Int {
        if (target.isEmpty()) return -1
        var i = minOf(fromIndex, source.size - target.size)
        while (i >= 0) {
            var matched = true
            for (j in target.indices) {
                if (source[i + j] != target[j]) {
                    matched = false
                    break
                }
            }
            if (matched) return i
            i--
        }
        return -1
    }

    private fun looksLikeMp4(bytes: ByteArray, start: Int): Boolean {
        if (start < 0 || start + 12 > bytes.size) return false
        return bytes[start + 4] == 'f'.code.toByte() &&
                bytes[start + 5] == 't'.code.toByte() &&
                bytes[start + 6] == 'y'.code.toByte() &&
                bytes[start + 7] == 'p'.code.toByte()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }
}
