package com.example.safetyapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Foreground service that:
 *  - records your position every minute (kept on the phone as a trail),
 *  - texts it to your emergency contacts every N minutes,
 *  - sends one last alert when the battery drops to 5% or lower,
 *  - tries to send an alert when the phone starts shutting down.
 *
 * A phone that is completely switched off cannot send anything. These alerts
 * make sure your contacts already have your last known position.
 * Everything uses GPS and SMS, so no internet is needed.
 */
class TrackingService : Service() {

    companion object {
        @Volatile var running = false
        const val CHANNEL = "safety_tracking"
        const val NOTIF_ID = 4242
        private const val LOW_BATTERY_PERCENT = 5
        private const val TRAIL_LIMIT = 300
    }

    private var lm: LocationManager? = null
    private var last: Location? = null
    private var intervalMs = 10 * 60_000L
    private var lastSmsAt = 0L
    private var receiverRegistered = false

    private val locListener = object : LocationListener {
        override fun onLocationChanged(location: Location) { handleLocation(location) }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val systemReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_BATTERY_CHANGED -> checkBattery(intent)
                Intent.ACTION_SHUTDOWN -> onShutdown()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val fromIntent = intent?.getIntExtra("minutes", -1) ?: -1
        val prefs = prefs()
        val minutes = if (fromIntent > 0) fromIntent else prefs.getInt("track_minutes", 10)
        prefs.edit().putInt("track_minutes", minutes).apply()
        intervalMs = minutes * 60_000L

        startInForeground()

        if (!running) {
            running = true
            lastSmsAt = 0L
            registerLocation()
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(Intent.ACTION_SHUTDOWN)
            }
            // The battery action is sticky: registering returns the current state.
            val sticky = ContextCompat.registerReceiver(
                this, systemReceiver, filter, ContextCompat.RECEIVER_EXPORTED
            )
            receiverRegistered = true
            if (sticky != null) checkBattery(sticky)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        try { lm?.removeUpdates(locListener) } catch (_: Exception) {}
        if (receiverRegistered) {
            try { unregisterReceiver(systemReceiver) } catch (_: Exception) {}
            receiverRegistered = false
        }
        super.onDestroy()
    }

    private fun prefs() = getSharedPreferences(WearSosService.PREFS, Context.MODE_PRIVATE)

    // ---------- foreground notification ----------

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Location sharing", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val pending = if (open != null) {
            PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE)
        } else null

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL)
        else
            @Suppress("DEPRECATION") Notification.Builder(this)
        val minutes = (intervalMs / 60_000L).toInt()
        val notification = builder
            .setContentTitle("Safety App is sharing your location")
            .setContentText("Contacts get an SMS every $minutes min")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .apply { if (pending != null) setContentIntent(pending) }
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    // ---------- location ----------

    private fun registerLocation() {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        lm = manager
        try {
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (manager.isProviderEnabled(provider)) {
                    manager.requestLocationUpdates(provider, 60_000L, 0f, locListener, Looper.getMainLooper())
                }
            }
        } catch (_: SecurityException) {
            // Location permission missing: the service stays up but records nothing.
        }
    }

    private fun handleLocation(loc: Location) {
        last = loc
        saveLocation(loc)
        val now = System.currentTimeMillis()
        if (now - lastSmsAt >= intervalMs) {
            lastSmsAt = now
            send(
                SosSender.buildTrackingMessage("LIVE LOCATION", userName(), loc, batteryPercent(), "live tracking"),
                source = "tracking", record = false, loc = loc
            )
        }
    }

    private fun saveLocation(loc: Location) {
        val p = prefs()
        val arr = JSONArray(p.getString("trail", "[]") ?: "[]")
        arr.put(JSONArray().put(loc.latitude).put(loc.longitude).put(loc.time))
        val out = if (arr.length() > TRAIL_LIMIT) {
            val trimmed = JSONArray()
            for (i in arr.length() - TRAIL_LIMIT until arr.length()) trimmed.put(arr.get(i))
            trimmed
        } else arr
        p.edit().putString("trail", out.toString()).apply()
    }

    // ---------- battery and shutdown ----------

    private fun batteryPercent(): Int? {
        val i = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        return level * 100 / scale
    }

    private fun checkBattery(i: Intent) {
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return
        val pct = level * 100 / scale
        val charging = i.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
        val p = prefs()
        val alreadySent = p.getBoolean("low_battery_sent", false)
        if (!charging && pct <= LOW_BATTERY_PERCENT && !alreadySent) {
            p.edit().putBoolean("low_battery_sent", true).apply()
            val loc = last ?: SosSender.lastKnownLocation(this)
            send(
                SosSender.buildTrackingMessage("LOW BATTERY - phone may switch off soon", userName(), loc, pct, "battery alert"),
                source = "battery", record = true, loc = loc
            )
        } else if ((charging || pct >= 20) && alreadySent) {
            p.edit().putBoolean("low_battery_sent", false).apply()
        }
    }

    private fun onShutdown() {
        val loc = last ?: SosSender.lastKnownLocation(this)
        send(
            SosSender.buildTrackingMessage("PHONE SWITCHING OFF", userName(), loc, batteryPercent(), "shutdown alert"),
            source = "shutdown", record = true, loc = loc
        )
    }

    // ---------- sending ----------

    private fun userName(): String = prefs().getString("user_name", "") ?: ""

    private fun contacts(): List<String> {
        val out = mutableListOf<String>()
        val arr = JSONArray(prefs().getString("contacts_json", "[]") ?: "[]")
        for (i in 0 until arr.length()) out.add(arr.getString(i))
        return out
    }

    private fun send(text: String, source: String, record: Boolean, loc: Location?) {
        val numbers = contacts()
        if (numbers.isEmpty()) return
        SosSender.send(this, numbers, text) { failed ->
            if (record) appendEvent(source, loc, failed, text)
        }
    }

    /** Flutter imports these into the alert history the next time the app opens. */
    private fun appendEvent(source: String, loc: Location?, failed: List<String>, text: String) {
        val p = prefs()
        val pending = JSONArray(p.getString("pending_events", "[]") ?: "[]")
        pending.put(JSONObject().apply {
            put("time", System.currentTimeMillis())
            if (loc != null) { put("lat", loc.latitude); put("lng", loc.longitude) }
            put("source", source)
            put("delivered", failed.isEmpty())
            put("failed", JSONArray(failed))
            put("message", text)
        })
        p.edit().putString("pending_events", pending.toString()).apply()
    }
}
