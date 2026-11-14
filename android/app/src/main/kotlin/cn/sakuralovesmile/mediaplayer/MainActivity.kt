package cn.sakuralovesmile.mediaplayer

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // S18: Android picture-in-picture. The Dart side lives in
        // core/device/pip.dart (MethodChannelPipController); the manifest
        // declares supportsPictureInPicture and the configChanges keep the
        // activity (and playback) alive across the PIP transition.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> result.success(enterPip())
                    else -> result.notImplemented()
                }
            }
    }

    /// Enters PIP with a 16:9 window. Returns false below API 26 or when the
    /// system refuses the request; playback is never paused here.
    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: IllegalStateException) {
            // e.g. PIP disabled for this activity or the device is in a state
            // that forbids it; the player keeps running full-screen.
            false
        }
    }

    companion object {
        private const val PIP_CHANNEL = "media_player/pip"
    }
}