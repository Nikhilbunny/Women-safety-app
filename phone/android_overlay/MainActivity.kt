package com.example.safetyapp

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safety/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val numbers = call.argument<List<String>>("numbers") ?: emptyList()
                        val message = call.argument<String>("message") ?: ""
                        SosSender.send(this, numbers, message) { failed -> result.success(failed) }
                    }
                    "syncState" -> {
                        val prefs = getSharedPreferences(WearSosService.PREFS, Context.MODE_PRIVATE)
                        prefs.edit()
                            .putString("contacts_json", call.argument<String>("contactsJson") ?: "[]")
                            .putString("user_name", call.argument<String>("userName") ?: "")
                            .apply()
                        result.success(null)
                    }
                    "drainEvents" -> {
                        val prefs = getSharedPreferences(WearSosService.PREFS, Context.MODE_PRIVATE)
                        val raw = prefs.getString("pending_events", "[]") ?: "[]"
                        prefs.edit().remove("pending_events").apply()
                        result.success(raw)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
