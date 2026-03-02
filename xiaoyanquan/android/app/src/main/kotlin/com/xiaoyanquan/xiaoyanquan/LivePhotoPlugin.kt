package com.xiaoyanquan.xiaoyanquan

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android 不支持原生 Live Photo，此 plugin 仅提供 MethodChannel 桩。
 * Flutter 侧在 Android 上会显示静态图片 + 视频播放提示。
 */
class LivePhotoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.xiaoyanquan/live_photo")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveLivePhoto" -> {
                // Android 不支持保存 Live Photo
                result.error("UNSUPPORTED", "Live Photo is not supported on Android", null)
            }
            "requestPermission" -> {
                result.success(false)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
