package bf.kaj.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity: the fingerprint prompt (local_auth) is a fragment.
//
// The `bf.kaj.app/tone` channel is the app's own ring (alert_tone_io.dart):
// a bundled tone played through the notification volume — a phone on silent
// stays silent — and a short buzz. Done here rather than through a plugin:
// it is two calls, and no plugin was worth the weight for them.
//
// The notification channel is made at every start, before any push has
// arrived (batch 115): Android lists the app's notifications by channel,
// and FCM rings on this one (AndroidManifest's default_notification_channel_id,
// and the push Worker's channel_id). Making it again is a no-op; the
// person's own choices for it are kept by the system.
class MainActivity : FlutterFragmentActivity() {
    private var player: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertsChannel()
    }

    private fun createAlertsChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        try {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                ALERTS_CHANNEL,
                "Commandes et messages",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "Les commandes, les réservations et les messages de Mara"
            channel.enableVibration(true)
            manager.createNotificationChannel(channel)
        } catch (e: Exception) {
            // Never the reason the app does not open.
        }
    }

    companion object {
        const val ALERTS_CHANNEL = "mara_alerts"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bf.kaj.app/tone")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        play(call.argument<String>("asset"))
                        result.success(null)
                    }
                    "vibrate" -> {
                        vibrate()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun play(asset: String?) {
        if (asset == null) return
        try {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
            // WAV is stored uncompressed in the APK, so it opens as a file.
            val fd = assets.openFd(key)
            player?.release()
            val next = MediaPlayer()
            next.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            next.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            fd.close()
            next.setOnCompletionListener { done ->
                done.release()
                if (player === done) player = null
            }
            next.prepare()
            next.start()
            player = next
        } catch (e: Exception) {
            // Quiet rather than an error.
        }
    }

    private fun vibrate() {
        try {
            val vibrator = vibrator() ?: return
            if (!vibrator.hasVibrator()) return
            val pattern = longArrayOf(0, 180, 90, 180)
            if (Build.VERSION.SDK_INT >= 26) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                legacyVibrate(vibrator, pattern)
            }
        } catch (e: Exception) {
        }
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            legacyVibrator()
        }

    @Suppress("DEPRECATION")
    private fun legacyVibrator(): Vibrator? =
        getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    @Suppress("DEPRECATION")
    private fun legacyVibrate(vibrator: Vibrator, pattern: LongArray) {
        vibrator.vibrate(pattern, -1)
    }

    override fun onDestroy() {
        player?.release()
        player = null
        super.onDestroy()
    }
}
