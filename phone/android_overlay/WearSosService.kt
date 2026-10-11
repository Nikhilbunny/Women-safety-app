package com.example.safetyapp

import android.content.Context
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Receives "/sos" from the watch over Bluetooth (no internet) and sends the
 * SMS itself, so it works even if the Flutter UI is not running. Contacts and
 * name come from SharedPreferences, which the Flutter app keeps in sync.
 */
class WearSosService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/sos") return

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val numbers = mutableListOf<String>()
        val arr = JSONArray(prefs.getString("contacts_json", "[]") ?: "[]")
        for (i in 0 until arr.length()) numbers.add(arr.getString(i))
        val name = prefs.getString("user_name", "") ?: ""

        val loc = SosSender.lastKnownLocation(this)
        val message = SosSender.buildMessage(name, "watch", loc)

        // onMessageReceived runs on a background thread, so waiting here is fine.
        var failed: List<String> = numbers
        val latch = CountDownLatch(1)
        SosSender.send(this, numbers, message) { f -> failed = f; latch.countDown() }
        latch.await(25, TimeUnit.SECONDS)

        // Remember the event; Flutter imports it into the log on next launch
        // and re-queues any numbers that failed.
        val pending = JSONArray(prefs.getString("pending_events", "[]") ?: "[]")
        pending.put(JSONObject().apply {
            put("time", System.currentTimeMillis())
            if (loc != null) { put("lat", loc.latitude); put("lng", loc.longitude) }
            put("delivered", failed.isEmpty() && numbers.isNotEmpty())
            put("failed", JSONArray(failed))
            put("message", message)
        })
        prefs.edit().putString("pending_events", pending.toString()).apply()

        // Tell the watch what happened.
        val ack = (if (numbers.isEmpty()) "no_contacts" else if (failed.isEmpty()) "sent" else "queued").toByteArray()
        Wearable.getMessageClient(this).sendMessage(event.sourceNodeId, "/sos/ack", ack)
    }

    companion object {
        const val PREFS = "safety_native"
    }
}
