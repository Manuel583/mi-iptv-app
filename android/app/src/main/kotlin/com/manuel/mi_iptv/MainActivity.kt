package com.manuel.mi_iptv

import android.Manifest
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaScannerConnection
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
        AppUpdater.register(flutterEngine, this)
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
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                        } catch (_: Exception) {
                        }
                    }
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
                "displayInfo" -> result.success(displayInfo())
                "matchFrameRate" ->
                    result.success(matchFrameRate(call.argument<Double>("fps") ?: 0.0))
                "resetFrameRate" -> {
                    setPreferredMode(0)
                    result.success(null)
                }
                else -> if (!RecorderBridge.handle(this, call, result)) result.notImplemented()
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

    // ---------------------------------------------- Hercios de la pantalla

    @Suppress("DEPRECATION")
    private fun currentDisplay(): android.view.Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay

    /** Hercios actuales y modos que admite la pantalla. */
    private fun displayInfo(): Map<String, Any> {
        val d = currentDisplay() ?: return emptyMap()
        val info = HashMap<String, Any>()
        info["hz"] = d.refreshRate.toDouble()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val cur = d.mode
            info["modeId"] = cur.modeId
            info["width"] = cur.physicalWidth
            info["height"] = cur.physicalHeight
            info["modes"] = d.supportedModes
                .filter { it.physicalWidth == cur.physicalWidth && it.physicalHeight == cur.physicalHeight }
                .map { it.refreshRate.toDouble() }
                .distinct()
        }
        return info
    }

    /** Elige el modo de pantalla cuyos hercios encajan mejor con los fps del vídeo. */
    private fun matchFrameRate(fps: Double): Double {
        if (fps < 10 || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return 0.0
        val d = currentDisplay() ?: return 0.0
        val cur = d.mode
        var best: android.view.Display.Mode? = null
        var bestErr = Double.MAX_VALUE
        for (m in d.supportedModes) {
            if (m.physicalWidth != cur.physicalWidth || m.physicalHeight != cur.physicalHeight) continue
            val ratio = m.refreshRate / fps
            val n = Math.round(ratio)
            if (n < 1) continue
            val err = Math.abs(ratio - n) / n
            // Empate: se queda con el modo actual o con el de menos hercios (gasta menos batería).
            if (err < bestErr - 0.0005 ||
                (Math.abs(err - bestErr) <= 0.0005 && best != null &&
                    (m.modeId == cur.modeId || (best.modeId != cur.modeId && m.refreshRate < best.refreshRate)))
            ) {
                best = m
                bestErr = err
            }
        }
        if (best == null || bestErr > 0.01) {
            setPreferredMode(0)
            return 0.0
        }
        setPreferredMode(best.modeId)
        return best.refreshRate.toDouble()
    }

    private fun setPreferredMode(id: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val attrs = window.attributes
            if (attrs.preferredDisplayModeId != id) {
                attrs.preferredDisplayModeId = id
                window.attributes = attrs
            }
        } catch (_: Exception) {
        }
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
