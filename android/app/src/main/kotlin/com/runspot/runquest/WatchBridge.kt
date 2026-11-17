package com.runspot.runquest

import android.content.Context
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

class WatchBridge(context: Context, messenger: BinaryMessenger) : MessageClient.OnMessageReceivedListener {
    private val channel = MethodChannel(messenger, "runspot/watch")
    private val messages = Wearable.getMessageClient(context)
    private val data = Wearable.getDataClient(context)
    init {
        messages.addListener(this)
        channel.setMethodCallHandler { call, result ->
            if (call.method != "state") { result.notImplemented() } else {
                val request = PutDataMapRequest.create("/runspot/state")
                request.dataMap.putString("json", JSONObject(call.arguments as Map<*, *>).toString())
                data.putDataItem(request.asPutDataRequest().setUrgent())
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("connection", "워치에 연결하지 못했습니다.", null) }
            }
        }
    }
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/runspot/command" || event.data.size > 1024) return
        val json = try { JSONObject(String(event.data, Charsets.UTF_8)) } catch (_: Exception) { return }
        val args = mapOf("action" to json.optString("action"), "session" to json.optString("session"))
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod("command", args, object : MethodChannel.Result {
                override fun success(result: Any?) { reply(event.sourceNodeId, json.optString("request"), result == true) }
                override fun error(code: String, message: String?, details: Any?) { reply(event.sourceNodeId, json.optString("request"), false) }
                override fun notImplemented() { reply(event.sourceNodeId, json.optString("request"), false) }
            })
        }
    }
    private fun reply(node: String, request: String, ok: Boolean) {
        messages.sendMessage(node, "/runspot/result", JSONObject(mapOf("ok" to ok, "request" to request)).toString().toByteArray(Charsets.UTF_8))
    }
    fun close() { messages.removeListener(this); channel.setMethodCallHandler(null) }
}
