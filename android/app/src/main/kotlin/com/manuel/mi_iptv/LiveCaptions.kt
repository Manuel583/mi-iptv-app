package com.manuel.mi_iptv

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.annotation.TargetApi
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * Subtítulos en directo dentro de la app.
 *
 * 1. Capta SOLO el sonido que reproduce Mi IPTV (AudioPlaybackCapture).
 * 2. Se lo pasa al reconocedor de voz de Google del propio teléfono
 *    (sin internet cuando el idioma está descargado).
 * 3. Envía el texto a Flutter: "captionText" (parcial o definitivo)
 *    y "captionStatus" (estado o errores).
 */
@TargetApi(33)
class LiveCaptions(
    private val activity: Activity,
    private val emit: (String, Any?) -> Unit
) {
    companion object {
        const val REQ_PROJECTION = 2001
        const val REQ_MIC = 2002
        private const val RATE = 16000
    }

    private val main = Handler(Looper.getMainLooper())
    private var language = "es-ES"
    private var pendingResult: MethodChannel.Result? = null
    private var projectionResultCode = 0
    private var projectionData: Intent? = null

    private var projection: MediaProjection? = null
    private var record: AudioRecord? = null
    private var captureThread: Thread? = null
    private var recognizer: SpeechRecognizer? = null
    private var onDevice = true
    private var useFormatting = true
    private var sessionStart = 0L
    private var failures = 0
    private var readFd: ParcelFileDescriptor? = null

    @Volatile private var running = false
    @Volatile private var sink: ParcelFileDescriptor.AutoCloseOutputStream? = null

    val isRunning: Boolean get() = running

    fun isSupported(): Boolean = SpeechRecognizer.isRecognitionAvailable(activity)

    // ------------------------------------------------------------ Arranque

    fun start(lang: String, result: MethodChannel.Result) {
        if (running) {
            result.success("ok")
            return
        }
        pendingResult?.success("cancelled")
        pendingResult = result
        language = lang
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
        } else {
            askProjection()
        }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_MIC) return false
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            askProjection()
        } else {
            finishStart("denied")
        }
        return true
    }

    private fun askProjection() {
        val mpm = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            mpm.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            mpm.createScreenCaptureIntent()
        }
        try {
            activity.startActivityForResult(intent, REQ_PROJECTION)
        } catch (e: Exception) {
            finishStart("error:${e.message}")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PROJECTION) return false
        if (resultCode != Activity.RESULT_OK || data == null) {
            finishStart("denied")
            return true
        }
        projectionResultCode = resultCode
        projectionData = data
        // Android 14 exige un servicio en primer plano de tipo "mediaProjection"
        // antes de usar el permiso. Cuando el servicio esté listo llama a onServiceReady().
        PlaybackService.captionsActive = true
        try {
            val svc = Intent(activity, PlaybackService::class.java)
            svc.putExtra("title", PlaybackService.lastTitle)
            activity.startForegroundService(svc)
        } catch (e: Exception) {
            PlaybackService.captionsActive = false
            finishStart("error:${e.message}")
        }
        return true
    }

    /** Lo llama PlaybackService cuando ya está en primer plano. */
    fun onServiceReady() {
        val data = projectionData ?: return
        projectionData = null
        main.post { beginCapture(projectionResultCode, data) }
    }

    @SuppressLint("MissingPermission")
    private fun beginCapture(resultCode: Int, data: Intent) {
        try {
            val mpm = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = mpm.getMediaProjection(resultCode, data)
                ?: throw IllegalStateException("sin permiso de captura")
            mp.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    main.post {
                        if (running) {
                            stop()
                            emit("captionStatus", mapOf("status" to "stopped"))
                        }
                    }
                }
            }, main)
            projection = mp

            val config = AudioPlaybackCaptureConfiguration.Builder(mp)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .addMatchingUid(Process.myUid())
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(RATE)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build()
            val minBuf = AudioRecord.getMinBufferSize(
                RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            val rec = AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(minBuf * 4, RATE))
                .setAudioPlaybackCaptureConfig(config)
                .build()
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                throw IllegalStateException("no se pudo captar el sonido")
            }
            record = rec
            running = true
            failures = 0
            onDevice = SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
            useFormatting = true
            rec.startRecording()
            startCaptureThread(rec)
            createRecognizer()
            startSession()
            finishStart("ok")
        } catch (e: Exception) {
            stop()
            finishStart("error:${e.message}")
        }
    }

    private fun finishStart(status: String) {
        val r = pendingResult
        pendingResult = null
        r?.success(status)
    }

    // ------------------------------------------------------------ Sonido

    private fun startCaptureThread(rec: AudioRecord) {
        captureThread = Thread {
            val buf = ByteArray(RATE / 10 * 2) // 100 ms
            while (running) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                val out = sink ?: continue
                try {
                    out.write(buf, 0, n)
                } catch (_: IOException) {
                    // El reconocedor cerró esta sesión; se abrirá otra.
                    if (sink === out) sink = null
                }
            }
        }.apply {
            name = "subtitulos-audio"
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    // ------------------------------------------------------------ Reconocimiento

    private fun createRecognizer() {
        recognizer?.destroy()
        val r = if (onDevice) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        } else {
            SpeechRecognizer.createSpeechRecognizer(activity)
        }
        r.setRecognitionListener(listener)
        recognizer = r
    }

    private fun buildIntent(source: ParcelFileDescriptor?): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (source != null) {
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, source)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, RATE)
                // Sesión continua: sigue reconociendo mientras llegue sonido.
                putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            }
            if (useFormatting) {
                putExtra(
                    RecognizerIntent.EXTRA_ENABLE_FORMATTING,
                    RecognizerIntent.FORMATTING_OPTIMIZE_LATENCY
                )
            }
        }

    private fun startSession() {
        if (!running) return
        closePipe()
        try {
            val pipe = ParcelFileDescriptor.createPipe()
            readFd = pipe[0]
            sink = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
            sessionStart = System.currentTimeMillis()
            recognizer?.startListening(buildIntent(pipe[0]))
        } catch (e: Exception) {
            retry(1000)
        }
    }

    private fun closePipe() {
        val out = sink
        sink = null
        try { out?.close() } catch (_: Exception) {}
        try { readFd?.close() } catch (_: Exception) {}
        readFd = null
    }

    private fun retry(delayMs: Long) {
        if (!running) return
        main.removeCallbacksAndMessages(null)
        main.postDelayed({ startSession() }, delayMs)
    }

    private fun text(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            emit("captionStatus", mapOf("status" to "listening"))
        }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onPartialResults(partialResults: Bundle?) {
            val t = text(partialResults) ?: return
            if (t.isNotBlank()) emit("captionText", mapOf("text" to t, "final" to false))
        }

        override fun onSegmentResults(segmentResults: Bundle) {
            failures = 0
            val t = text(segmentResults) ?: return
            if (t.isNotBlank()) emit("captionText", mapOf("text" to t, "final" to true))
        }

        override fun onResults(results: Bundle?) {
            failures = 0
            val t = text(results)
            if (!t.isNullOrBlank()) emit("captionText", mapOf("text" to t, "final" to true))
            retry(50)
        }

        override fun onEndOfSegmentedSession() {
            retry(50)
        }

        override fun onError(error: Int) {
            if (!running) return
            val quick = System.currentTimeMillis() - sessionStart < 1500
            when (error) {
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
                    if (onDevice) {
                        emit("captionStatus", mapOf("status" to "downloading"))
                        try {
                            recognizer?.triggerModelDownload(buildIntent(null))
                        } catch (_: Exception) {}
                        // Mientras se descarga, se usa el reconocedor normal de Google.
                        onDevice = false
                        createRecognizer()
                        retry(500)
                    } else {
                        fail("El idioma elegido no está disponible en este teléfono")
                    }
                }
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> retry(50)
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    fail("Falta el permiso de micrófono para Mi IPTV")
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> {
                    createRecognizer()
                    retry(500)
                }
                else -> {
                    failures++
                    if (quick && useFormatting) {
                        // Algunos teléfonos no aceptan la puntuación automática.
                        useFormatting = false
                        retry(200)
                    } else if (failures >= 5 && onDevice) {
                        onDevice = false
                        failures = 0
                        createRecognizer()
                        retry(500)
                    } else if (failures >= 8) {
                        fail("El reconocimiento de voz ha fallado (código $error)")
                    } else {
                        retry(800)
                    }
                }
            }
        }
    }

    private fun fail(message: String) {
        stop()
        emit("captionStatus", mapOf("status" to "error", "message" to message))
    }

    // ------------------------------------------------------------ Parada

    fun stop() {
        running = false
        main.removeCallbacksAndMessages(null)
        try { recognizer?.cancel() } catch (_: Exception) {}
        try { recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null
        closePipe()
        try { record?.stop() } catch (_: Exception) {}
        try { captureThread?.join(300) } catch (_: Exception) {}
        captureThread = null
        try { record?.release() } catch (_: Exception) {}
        record = null
        val mp = projection
        projection = null
        try { mp?.stop() } catch (_: Exception) {}
        PlaybackService.captionsActive = false
    }
}
