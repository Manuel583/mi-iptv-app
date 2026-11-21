package com.manuel.mi_iptv

import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/*
 * Grabación programada en Android.
 *
 * La app entrega la lista de grabaciones pendientes. Para cada una se pone
 * una alarma exacta; a la hora indicada RecorderReceiver arranca
 * RecorderService, que descarga la emisión a un archivo (.ts) en
 * Películas/Mi IPTV hasta la hora de fin. Funciona con la app cerrada.
 * Tras reiniciar el móvil, las alarmas se vuelven a poner.
 */

object RecorderStore {
    private const val PREFS = "grabaciones"

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun items(c: Context): JSONArray =
        try { JSONArray(prefs(c).getString("items", "[]")) } catch (_: Exception) { JSONArray() }

    fun setItems(c: Context, a: JSONArray) {
        prefs(c).edit().putString("items", a.toString()).apply()
    }

    fun find(c: Context, id: String): JSONObject? {
        val a = items(c)
        for (i in 0 until a.length()) {
            val o = a.optJSONObject(i) ?: continue
            if (o.optString("id") == id) return o
        }
        return null
    }

    @Synchronized
    fun statuses(c: Context): JSONObject =
        try { JSONObject(prefs(c).getString("status", "{}")!!) } catch (_: Exception) { JSONObject() }

    @Synchronized
    fun setStatus(c: Context, id: String, status: String, path: String = "", error: String = "", bytes: Long = 0) {
        val all = statuses(c)
        all.put(id, JSONObject().apply {
            put("status", status)
            put("path", path)
            put("error", error)
            put("bytes", bytes)
            put("t", System.currentTimeMillis())
        })
        // No guardar estados de hace más de 60 días.
        val old = System.currentTimeMillis() - 60L * 24 * 3600 * 1000
        val keys = all.keys().asSequence().toList()
        for (k in keys) {
            if ((all.optJSONObject(k)?.optLong("t") ?: 0L) < old) all.remove(k)
        }
        prefs(c).edit().putString("status", all.toString()).apply()
    }

    fun armedIds(c: Context): Set<String> = prefs(c).getStringSet("armed", emptySet()) ?: emptySet()

    fun setArmedIds(c: Context, ids: Set<String>) {
        prefs(c).edit().putStringSet("armed", ids).apply()
    }
}

object RecorderAlarms {
    const val ACTION_ALARM = "com.manuel.mi_iptv.GRABAR"

    private fun pending(c: Context, id: String): PendingIntent {
        val i = Intent(c, RecorderReceiver::class.java).setAction(ACTION_ALARM).putExtra("id", id)
        return PendingIntent.getBroadcast(
            c, id.hashCode(), i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Pone una alarma por cada grabación pendiente y quita las que sobran. */
    fun arm(c: Context, fromApp: Boolean = false): Boolean {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val items = RecorderStore.items(c)
        val now = System.currentTimeMillis()
        val ids = mutableSetOf<String>()
        var ok = true
        for (i in 0 until items.length()) {
            val o = items.optJSONObject(i) ?: continue
            val id = o.optString("id")
            val start = o.optLong("start")
            val stop = o.optLong("stop")
            if (id.isEmpty() || stop <= now) continue
            ids.add(id)
            if (start <= now + 5000 && fromApp) {
                // Ya debería estar grabando.
                RecorderService.start(c, id)
                continue
            }
            // Tras reiniciar, Android no deja empezar directamente: se
            // pone una alarma para dentro de unos segundos.
            val at = maxOf(start, now + 10000)
            try {
                val pi = pending(c, id)
                val exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
                if (exact) {
                    // Como un despertador: es lo más fiable, incluso con el
                    // móvil en reposo.
                    val show = PendingIntent.getActivity(
                        c, 0, Intent(c, MainActivity::class.java),
                        PendingIntent.FLAG_IMMUTABLE
                    )
                    am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), pi)
                } else {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                }
            } catch (_: Exception) {
                ok = false
            }
        }
        for (old in RecorderStore.armedIds(c)) {
            if (old !in ids) {
                try { am.cancel(pending(c, old)) } catch (_: Exception) {}
            }
        }
        RecorderStore.setArmedIds(c, ids)
        return ok
    }
}

class RecorderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            RecorderAlarms.ACTION_ALARM -> {
                val id = intent.getStringExtra("id") ?: return
                RecorderService.start(context, id)
            }
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> RecorderAlarms.arm(context)
        }
    }
}

class RecorderService : Service() {
    companion object {
        const val CHANNEL_ID = "grabaciones"
        const val NOTIFICATION_ID = 8
        const val ACTION_STOP = "com.manuel.mi_iptv.PARAR_GRABACION"
        private val jobs = ConcurrentHashMap<String, Job>()

        fun start(c: Context, id: String) {
            try {
                val i = Intent(c, RecorderService::class.java).putExtra("id", id)
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i) else c.startService(i)
            } catch (e: Exception) {
                RecorderStore.setStatus(c, id, "failed", error = "Android no dejó empezar: ${e.message}")
            }
        }

        fun cancel(id: String) {
            jobs[id]?.cancelled = true
        }
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        goForeground()
        if (intent?.action == ACTION_STOP) {
            for (j in jobs.values) j.cancelled = true
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra("id")
        val item = if (id != null) RecorderStore.find(this, id) else null
        if (id == null || item == null) {
            if (jobs.isEmpty()) stopSelfCompat()
            return START_NOT_STICKY
        }
        if (jobs.containsKey(id)) return START_NOT_STICKY
        val stop = item.optLong("stop")
        if (stop <= System.currentTimeMillis()) {
            RecorderStore.setStatus(this, id, "failed", error = "El programa ya había terminado.")
            if (jobs.isEmpty()) stopSelfCompat()
            return START_NOT_STICKY
        }
        acquireLocks()
        val out = File(folder(), item.optString("fileName", "Grabacion $id.ts"))
        val job = Job(
            this, id, item.optString("url"), item.optString("userAgent"),
            item.optString("referrer"), stop, out,
            "${item.optString("channel")} | ${item.optString("title")}"
        )
        jobs[id] = job
        RecorderStore.setStatus(this, id, "recording", out.absolutePath)
        updateNotification()
        Thread {
            job.run()
            jobs.remove(id)
            val ok = job.bytes > 0
            if (ok) {
                try { MediaScannerConnection.scanFile(this, arrayOf(out.absolutePath), null, null) } catch (_: Exception) {}
            } else {
                try { out.delete() } catch (_: Exception) {}
            }
            RecorderStore.setStatus(
                this, id, if (ok) "done" else "failed",
                if (ok) out.absolutePath else "",
                if (ok) "" else (job.lastError.ifEmpty { "No llegó vídeo." }),
                job.bytes
            )
            if (jobs.isEmpty()) {
                releaseLocks()
                stopSelfCompat()
            } else {
                updateNotification()
            }
        }.start()
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 limita las tareas de datos a 6 horas al día.
        for (j in jobs.values) {
            j.lastError = "Android detuvo la grabación por durar demasiado."
            j.cancelled = true
        }
    }

    override fun onDestroy() {
        for (j in jobs.values) j.cancelled = true
        releaseLocks()
        super.onDestroy()
    }

    private fun folder(): File {
        val candidates = mutableListOf<File>()
        @Suppress("DEPRECATION")
        candidates.add(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Mi IPTV"))
        getExternalFilesDir(null)?.let { candidates.add(File(it, "Grabaciones")) }
        candidates.add(File(filesDir, "Grabaciones"))
        for (d in candidates) {
            try {
                d.mkdirs()
                val probe = File(d, ".prueba.ts")
                probe.writeText("x")
                probe.delete()
                return d
            } catch (_: Exception) {
            }
        }
        return filesDir
    }

    private fun acquireLocks() {
        if (wake == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mi_iptv:grabacion").apply {
                setReferenceCounted(false)
                acquire(13L * 3600 * 1000)
            }
        }
        if (wifi == null) {
            try {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "mi_iptv:grabacion").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun releaseLocks() {
        try { wake?.release() } catch (_: Exception) {}
        try { wifi?.release() } catch (_: Exception) {}
        wake = null
        wifi = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val m = getSystemService(NotificationManager::class.java)
            if (m.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, "Grabaciones", NotificationManager.IMPORTANCE_LOW)
                ch.description = "Grabaciones programadas en curso"
                ch.setShowBadge(false)
                m.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, RecorderService::class.java).setAction(ACTION_STOP), flags
        )
        val b = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val titles = jobs.values.map { it.label }
        b.setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle(if (titles.size > 1) "Grabando ${titles.size} programas" else "Grabando")
            .setContentText(titles.joinToString(" | ").ifEmpty { "Preparando la grabación…" })
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_media_pause),
                    "Parar y guardar", stop
                ).build()
            )
        return b.build()
    }

    private fun goForeground() {
        val n = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (_: Exception) {
        }
    }

    private fun updateNotification() {
        try {
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {
        }
    }

    private fun stopSelfCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Una grabación: descarga la emisión hasta la hora de fin. */
    class Job(
        private val ctx: Context,
        val id: String,
        private val url: String,
        private val userAgent: String,
        private val referrer: String,
        private val stopAt: Long,
        private val out: File,
        val label: String,
    ) {
        @Volatile var cancelled = false
        @Volatile var bytes = 0L
        @Volatile var lastError = ""
        private var lastStatus = 0L

        private fun done() = cancelled || System.currentTimeMillis() >= stopAt

        fun run() {
            out.parentFile?.mkdirs()
            FileOutputStream(out, true).use { sink ->
                while (!done()) {
                    try {
                        val conn = open(url)
                        val type = conn.contentType ?: ""
                        val finalUrl = conn.url.toString()
                        val hls = type.contains("mpegurl", true) ||
                            Uri.parse(url).path?.lowercase()?.endsWith(".m3u8") == true
                        if (hls) {
                            val text = conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
                            conn.disconnect()
                            recordHls(finalUrl, text, sink)
                        } else {
                            try { copy(conn.inputStream, sink) } finally { conn.disconnect() }
                        }
                    } catch (e: Exception) {
                        lastError = e.message ?: e.toString()
                    }
                    if (!done()) sleep(3000)
                }
            }
        }

        private fun sleep(ms: Long) {
            val end = System.currentTimeMillis() + ms
            while (!done() && System.currentTimeMillis() < end) Thread.sleep(250)
        }

        private fun open(u: String): HttpURLConnection {
            val c = URL(u).openConnection() as HttpURLConnection
            c.connectTimeout = 20000
            c.readTimeout = 20000
            c.instanceFollowRedirects = true
            c.setRequestProperty("User-Agent", userAgent.ifEmpty { "VLC/3.0.20 LibVLC/3.0.20" })
            if (referrer.isNotEmpty()) c.setRequestProperty("Referer", referrer)
            val code = c.responseCode
            if (code >= 400) {
                c.disconnect()
                throw Exception("El servidor respondió $code")
            }
            return c
        }

        private fun copy(input: InputStream, sink: OutputStream) {
            val buf = ByteArray(64 * 1024)
            input.use {
                while (!done()) {
                    val n = it.read(buf)
                    if (n < 0) break
                    sink.write(buf, 0, n)
                    bytes += n
                    reportProgress()
                }
            }
            sink.flush()
        }

        private fun reportProgress() {
            val now = System.currentTimeMillis()
            if (now - lastStatus > 30000) {
                lastStatus = now
                RecorderStore.setStatus(ctx, id, "recording", out.absolutePath, bytes = bytes)
            }
        }

        private fun fetchText(u: String): String {
            val c = open(u)
            try {
                return c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            } finally {
                c.disconnect()
            }
        }

        private fun resolve(base: String, ref: String): String = URL(URL(base), ref).toString()

        private fun recordHls(playlistUrl: String, firstText: String, sink: OutputStream) {
            var media = playlistUrl
            var text = firstText
            if (text.contains("#EXT-X-STREAM-INF")) {
                // Lista maestra: la calidad más alta.
                val lines = text.lines()
                var best: String? = null
                var bestBw = -1L
                for (i in lines.indices) {
                    val l = lines[i].trim()
                    if (!l.startsWith("#EXT-X-STREAM-INF")) continue
                    val bw = Regex("[:,]BANDWIDTH=(\\d+)").find(l)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
                    val u = lines.drop(i + 1).map { it.trim() }.firstOrNull { it.isNotEmpty() && !it.startsWith("#") }
                    if (u != null && bw > bestBw) {
                        bestBw = bw
                        best = u
                    }
                }
                media = resolve(playlistUrl, best ?: throw Exception("Lista HLS vacía"))
                text = fetchText(media)
            }
            val seen = LinkedHashSet<String>()
            var initDone = false
            while (!done()) {
                var target = 6
                var ended = false
                val segs = mutableListOf<String>()
                for (raw in text.lines()) {
                    val l = raw.trim()
                    when {
                        l.isEmpty() -> {}
                        l.startsWith("#EXT-X-TARGETDURATION:") -> target = l.substring(22).trim().toIntOrNull() ?: target
                        l.startsWith("#EXT-X-ENDLIST") -> ended = true
                        l.startsWith("#EXT-X-MAP:") -> {
                            val init = Regex("URI=\"([^\"]+)\"").find(l)?.groupValues?.get(1)
                            if (init != null && !initDone) {
                                val c = open(resolve(media, init))
                                try { copy(c.inputStream, sink) } finally { c.disconnect() }
                                initDone = true
                            }
                        }
                        !l.startsWith("#") -> segs.add(l)
                    }
                }
                for (s in segs) {
                    if (done()) break
                    if (!seen.add(s)) continue
                    if (seen.size > 2000) seen.remove(seen.first())
                    try {
                        val c = open(resolve(media, s))
                        try { copy(c.inputStream, sink) } finally { c.disconnect() }
                    } catch (e: Exception) {
                        lastError = e.message ?: e.toString()
                    }
                }
                if (ended || done()) break
                sleep((target * 500L).coerceIn(1000L, 6000L))
                if (done()) break
                text = fetchText(media)
            }
        }
    }
}

/** Llamadas desde la app (canal mi_iptv/native). */
object RecorderBridge {
    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "recorderSchedule" -> {
                val json = call.argument<String>("items") ?: "[]"
                val ok = try {
                    RecorderStore.setItems(activity, JSONArray(json))
                    RecorderAlarms.arm(activity, fromApp = true)
                } catch (_: Exception) {
                    false
                }
                result.success(ok)
            }
            "recorderCancel" -> {
                val id = call.argument<String>("id")
                if (id != null) RecorderService.cancel(id)
                result.success(null)
            }
            "recorderStatuses" -> result.success(RecorderStore.statuses(activity).toString())
            "batteryRestricted" -> {
                val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(!pm.isIgnoringBatteryOptimizations(activity.packageName))
            }
            "askBatteryExemption" -> {
                try {
                    @Suppress("BatteryLife")
                    val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        .setData(Uri.parse("package:${activity.packageName}"))
                    activity.startActivity(i)
                } catch (_: Exception) {
                    try {
                        activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    } catch (_: Exception) {
                    }
                }
                result.success(null)
            }
            else -> return false
        }
        return true
    }
}
