package com.example.safetyapp

import android.content.Context
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { SosScreen() } }
    }
}

/** Sends "/sos" to every paired phone node over Bluetooth. No internet involved. */
object SosClient {
    /** Returns true if at least one phone accepted the message. */
    suspend fun send(ctx: Context): Boolean {
        val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
        if (nodes.isEmpty()) return false
        val payload = """{"t":${System.currentTimeMillis()},"src":"watch"}""".toByteArray()
        var ok = false
        for (n in nodes) {
            try {
                Wearable.getMessageClient(ctx).sendMessage(n.id, "/sos", payload).await()
                ok = true
            } catch (_: Exception) { }
        }
        return ok
    }
}

@Composable
fun SosScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf("Hold to send SOS") }
    var sending by remember { mutableStateOf(false) }

    // The phone answers "/sos/ack" once it has sent (or queued) the SMS.
    DisposableEffect(Unit) {
        val listener = MessageClient.OnMessageReceivedListener { e ->
            if (e.path == "/sos/ack") {
                status = when (String(e.data)) {
                    "sent" -> "Alert sent"
                    "queued" -> "No signal - queued on phone"
                    "no_contacts" -> "Add contacts on phone"
                    else -> "Phone replied"
                }
                sending = false
            }
        }
        Wearable.getMessageClient(ctx).addListener(listener)
        onDispose { Wearable.getMessageClient(ctx).removeListener(listener) }
    }

    fun buzz() {
        val v = ctx.getSystemService(Vibrator::class.java)
        v?.vibrate(VibrationEffect.createOneShot(300, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun fire() {
        if (sending) return
        sending = true
        buzz()
        scope.launch {
            // Phone may be briefly out of Bluetooth range: retry for about a minute.
            repeat(6) { attempt ->
                status = if (attempt == 0) "Sending..." else "Phone not found, retry ${attempt + 1}/6"
                if (SosClient.send(ctx)) {
                    status = "Sent to phone..."
                    // Allow another press if the phone never confirms.
                    delay(30_000)
                    sending = false
                    return@launch
                }
                delay(10_000)
            }
            status = "Phone not reachable. Call for help."
            sending = false
        }
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(110.dp)
                .background(Color(0xFFB3261E), CircleShape)
                // Long press = deliberate action, avoids accidental alerts.
                .pointerInput(Unit) { detectTapGestures(onLongPress = { fire() }) },
            contentAlignment = Alignment.Center
        ) {
            Text("SOS", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        }
        Text(
            text = status,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}
