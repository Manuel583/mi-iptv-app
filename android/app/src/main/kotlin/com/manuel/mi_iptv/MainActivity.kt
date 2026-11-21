package com.manuel.mi_iptv

import android.Manifest
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        var instance: MainActivity? = null
    }

    private var channel: MethodChannel? = null
    var captions: LiveCaptions? = null
    private var pipEnabled = false
    private var askedNotifications = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mi_iptv/native")
        channel = ch
        if (Build.VERSION.SDK_INT >= 33) {
            captions = LiveCaptions(this) { method, args ->
                runOnUiThread { channel?.invokeMethod(method, args) }
            }
        }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> result.success(pipSupported())
                "setPipEnabled" -> {
                    pipEnabled = call.argument<Boolean>("enabled") ?: false
                    updatePipParams()
                    result.success(null)
                }
                "enterPip" -> result.success(enterPip())
                "startService" -> {
                    requestNotificationPermission()
                    startPlaybackService(call.argument<String>("title") ?: "Mi IPTV")
                    result.success(null)
                }
                "stopService" -> {
                    stopPlaybackService()
                    result.success(null)
                }
                "captionsSupported" -> result.success(captions?.isSupported() == true)
                "startCaptions" ->
                    captions?.start(call.argument<String>("lang") ?: "es-ES", result)
                        ?: result.success("unsupported")
                "stopCaptions" -> {
                    captions?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (captions?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (captions?.onPermissionResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        captions?.stop()
        stopPlaybackService()
        if (instance == this) instance = null
        super.onDestroy()
    }

    fun requestStopFromNotification() {
        channel?.invokeMethod("stopPlayback", null)
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun buildPipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipEnabled)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (!pipSupported()) return
        try {
            buildPipParams()?.let { setPictureInPictureParams(it) }
        } catch (_: Exception) {
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            val params = buildPipParams() ?: return false
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // En Android 12 o superior la entrada es automática (setAutoEnterEnabled).
        if (pipEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    private fun requestNotificationPermission() {
        if (askedNotifications) return
        askedNotifications = true
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    private fun startPlaybackService(title: String) {
        try {
            val intent = Intent(this, PlaybackService::class.java)
            intent.putExtra("title", title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
        }
    }

    private fun stopPlaybackService() {
        try {
            stopService(Intent(this, PlaybackService::class.java))
        } catch (_: Exception) {
        }
    }
}
