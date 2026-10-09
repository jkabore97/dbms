package bf.kaj.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
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
        const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
        const val NOTIFY_PREFS = "mara_notify"
        const val REFUSED = "refused"
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
        // The notification permission as the system has it (120), and the
        // app's own notification settings — what Firebase cannot answer:
        // it says « denied » alike for a phone never asked and for one that
        // refused for good (push_client_stub.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bf.kaj.app/notify")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permission" -> result.success(notificationPermission())
                    "answered" -> {
                        noteAnswer()
                        result.success(null)
                    }
                    "openSettings" -> result.success(openNotificationSettings())
                    else -> result.notImplemented()
                }
            }
    }

    // "granted", "prompt" (the system's question can still be shown) or
    // "blocked" (only the settings can turn it on). Before Android 13 there
    // is no question: notifications are on unless switched off in settings.
    private fun notificationPermission(): String {
        val enabled = try {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        } catch (e: Exception) {
            true
        }
        if (Build.VERSION.SDK_INT < 33) return if (enabled) "granted" else "blocked"
        val allowed = ContextCompat.checkSelfPermission(this, POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (allowed) return if (enabled) "granted" else "blocked"
        // Refused twice (or « ne plus demander »): the system no longer
        // shows its question, and no longer wants a reason shown either —
        // as before any answer, hence the refusal noted by noteAnswer().
        val refused = getSharedPreferences(NOTIFY_PREFS, Context.MODE_PRIVATE)
            .getBoolean(REFUSED, false)
        return if (refused && !shouldShowRequestPermissionRationale(POST_NOTIFICATIONS)) {
            "blocked"
        } else {
            "prompt"
        }
    }

    // After the system's question has returned (push_client_stub.dart's
    // ask): a real refusal is the only answer after which the system wants
    // a reason shown. A dialog dismissed without an answer (back, a tap
    // beside it) leaves no reason to show, and is not noted: the phone can
    // still be asked, never « blocked » for it.
    private fun noteAnswer() {
        if (Build.VERSION.SDK_INT < 33) return
        try {
            if (shouldShowRequestPermissionRationale(POST_NOTIFICATIONS)) {
                getSharedPreferences(NOTIFY_PREFS, Context.MODE_PRIVATE)
                    .edit().putBoolean(REFUSED, true).apply()
            }
        } catch (e: Exception) {
            // Not noted: at worst « prompt » for a phone that would not ask.
        }
    }

    private fun openNotificationSettings(): Boolean {
        val notifications = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            null
        }
        val details = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        for (intent in listOfNotNull(notifications, details)) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // The next way in.
            }
        }
        return false
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
