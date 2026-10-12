package com.example.safetyapp

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper

/**
 * Plays a looping alarm on the ALARM audio stream, so it is loud even when the
 * ringer is silent. Raises the alarm volume to maximum while playing and puts
 * it back afterwards. Stops by itself after five minutes.
 */
object AlarmPlayer {
    private var player: MediaPlayer? = null
    private var savedVolume = -1
    private val handler = Handler(Looper.getMainLooper())
    private const val MAX_PLAY_MS = 5 * 60_000L

    val playing: Boolean get() = player != null

    fun start(context: Context, sound: String): Boolean {
        stop(context)
        val app = context.applicationContext
        val name = if (sound == "pulse") "alarm_pulse" else "alarm_siren"
        val resId = app.resources.getIdentifier(name, "raw", app.packageName)
        if (resId == 0) return false

        val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (_: Exception) {
            savedVolume = -1
        }

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val mp = MediaPlayer.create(app, resId, attrs, AudioManager.AUDIO_SESSION_ID_GENERATE)
        if (mp == null) {
            restoreVolume(app)
            return false
        }
        mp.isLooping = true
        mp.start()
        player = mp
        handler.postDelayed({ stop(app) }, MAX_PLAY_MS)
        return true
    }

    fun stop(context: Context) {
        handler.removeCallbacksAndMessages(null)
        val mp = player
        player = null
        if (mp != null) {
            try { mp.stop() } catch (_: Exception) {}
            try { mp.release() } catch (_: Exception) {}
        }
        restoreVolume(context.applicationContext)
    }

    private fun restoreVolume(app: Context) {
        if (savedVolume < 0) return
        try {
            val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
        } catch (_: Exception) {}
        savedVolume = -1
    }
}
