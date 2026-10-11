package com.example.safetyapp

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicInteger

/**
 * Sends SMS over the cellular network (no internet needed) and reports which
 * numbers did NOT go out, so the caller can queue them for a retry.
 */
object SosSender {
    private val requestCodes = AtomicInteger(1000)
    private const val TIMEOUT_MS = 20_000L

    private fun smsManager(c: Context): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            c.getSystemService(SmsManager::class.java)
        else
            @Suppress("DEPRECATION") SmsManager.getDefault()

    /** [onDone] receives the numbers that failed (empty list = all sent). Called on the main thread. */
    fun send(context: Context, numbers: List<String>, message: String, onDone: (List<String>) -> Unit) {
        val app = context.applicationContext
        if (numbers.isEmpty()) { onDone(emptyList()); return }
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED) {
            onDone(numbers); return
        }

        val sms = smsManager(app)
        val parts = sms.divideMessage(message)
        val action = "com.example.safetyapp.SMS_SENT_" + System.nanoTime()
        val okParts = HashMap<String, Int>()
        val failed = LinkedHashSet<String>()
        var received = 0
        var finished = false
        val expected = numbers.size * parts.size
        val handler = Handler(Looper.getMainLooper())
        lateinit var receiver: BroadcastReceiver

        fun finish() {
            if (finished) return
            finished = true
            try { app.unregisterReceiver(receiver) } catch (_: Exception) {}
            // Anything not confirmed OK (including timeouts) counts as failed.
            val result = numbers.filter { failed.contains(it) || (okParts[it] ?: 0) < parts.size }
            onDone(result)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                val num = i.getStringExtra("num") ?: return
                if (resultCode == Activity.RESULT_OK) okParts[num] = (okParts[num] ?: 0) + 1
                else failed.add(num)
                received++
                if (received >= expected) finish()
            }
        }
        ContextCompat.registerReceiver(app, receiver, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED)
        handler.postDelayed({ finish() }, TIMEOUT_MS)

        for (n in numbers) {
            try {
                val sentIntents = ArrayList<PendingIntent>()
                for (p in parts.indices) {
                    val intent = Intent(action).setPackage(app.packageName).putExtra("num", n)
                    sentIntents.add(
                        PendingIntent.getBroadcast(
                            app, requestCodes.incrementAndGet(), intent,
                            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                        )
                    )
                }
                sms.sendMultipartTextMessage(n, null, parts, sentIntents, null)
            } catch (e: Exception) {
                failed.add(n)
                received += parts.size
                if (received >= expected) finish()
            }
        }
    }

    /** Most recent cached fix from any provider. Needs no network. */
    fun lastKnownLocation(context: Context): Location? {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) return null
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var best: Location? = null
        for (provider in lm.getProviders(true)) {
            val loc = try { lm.getLastKnownLocation(provider) } catch (_: SecurityException) { null } ?: continue
            if (best == null || loc.time > best.time) best = loc
        }
        return best
    }

    /** Message for live tracking, low battery and shutdown alerts. Plain characters only. */
    fun buildTrackingMessage(headline: String, name: String, loc: Location?, battery: Int?, via: String): String {
        val sb = StringBuilder()
        val who = if (name.isBlank()) "Someone" else name
        sb.append(headline).append(" - ").append(who).append("\n")
        val fmt = java.text.SimpleDateFormat("dd MMM yyyy HH:mm", java.util.Locale.ENGLISH)
        sb.append("Time: ").append(fmt.format(java.util.Date())).append("\n")
        if (loc != null) {
            val lat = String.format(java.util.Locale.US, "%.5f", loc.latitude)
            val lng = String.format(java.util.Locale.US, "%.5f", loc.longitude)
            val ageMin = (System.currentTimeMillis() - loc.time) / 60000
            sb.append("Location: ").append(lat).append(", ").append(lng)
            if (ageMin >= 2) sb.append(" [").append(ageMin).append(" min old]")
            sb.append("\nMap: https://maps.google.com/?q=").append(lat).append(",").append(lng).append("\n")
        } else {
            sb.append("Location: unavailable.\n")
        }
        if (battery != null) sb.append("Battery: ").append(battery).append("%\n")
        sb.append("Sent by Safety App (").append(via).append(").")
        return sb.toString()
    }

    fun buildMessage(name: String, source: String, loc: Location?): String {
        val sb = StringBuilder()
        val who = if (name.isBlank()) "Someone" else name
        sb.append("EMERGENCY - ").append(who).append(" needs help.\n")
        val fmt = java.text.SimpleDateFormat("dd MMM yyyy HH:mm", java.util.Locale.ENGLISH)
        sb.append("Time: ").append(fmt.format(java.util.Date())).append("\n")
        if (loc != null) {
            val lat = String.format(java.util.Locale.US, "%.5f", loc.latitude)
            val lng = String.format(java.util.Locale.US, "%.5f", loc.longitude)
            val ageSec = (System.currentTimeMillis() - loc.time) / 1000
            sb.append("Location: ").append(lat).append(", ").append(lng)
            if (ageSec > 60) sb.append(" [last known]")
            sb.append("\nMap: https://maps.google.com/?q=").append(lat).append(",").append(lng).append("\n")
        } else {
            sb.append("Location: unavailable. Please call now.\n")
        }
        sb.append("Sent by Safety App via ").append(source).append(".")
        return sb.toString()
    }
}
