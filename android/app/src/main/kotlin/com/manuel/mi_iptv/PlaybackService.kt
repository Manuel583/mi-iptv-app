package com.manuel.mi_iptv

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Servicio en primer plano que mantiene el sonido cuando la app
 * está en segundo plano y muestra una notificación con "Detener".
 */
class PlaybackService : Service() {
    companion object {
        const val CHANNEL_ID = "reproduccion"
        const val NOTIFICATION_ID = 7
        const val ACTION_STOP = "com.manuel.mi_iptv.STOP"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            MainActivity.instance?.requestStopFromNotification()
            stopSelfCompat()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra("title") ?: "Mi IPTV"
        createChannel()
        val notification = buildNotification(title)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun stopSelfCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        stopSelf()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Reproducción",
                    NotificationManager.IMPORTANCE_LOW
                )
                ch.description = "Canal que se está reproduciendo"
                ch.setShowBadge(false)
                manager.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(title: String): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val openIntent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open = PendingIntent.getActivity(this, 0, openIntent, flags)
        val stopIntent = Intent(this, PlaybackService::class.java).setAction(ACTION_STOP)
        val stop = PendingIntent.getService(this, 1, stopIntent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText("Reproduciendo en Mi IPTV")
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
        val action = Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_media_pause),
            "Detener",
            stop
        ).build()
        builder.addAction(action)
        return builder.build()
    }
}
