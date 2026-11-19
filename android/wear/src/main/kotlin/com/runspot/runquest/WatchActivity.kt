package com.runspot.runquest

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.*
import android.view.Gravity
import com.google.android.gms.wearable.*
import org.json.JSONObject
import java.util.Locale

class WatchActivity : Activity(), DataClient.OnDataChangedListener, MessageClient.OnMessageReceivedListener {
    private var state = JSONObject()
    private var source: String? = null
    private lateinit var metrics: TextView
    private lateinit var status: TextView
    private lateinit var control: Button
    private val handler = Handler(Looper.getMainLooper())
    private var pending = false
    private var requestId: String? = null
    private val tick = object : Runnable { override fun run() { render(); handler.postDelayed(this, 1000) } }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(24, 24, 24, 24) }
        layout.addView(TextView(this).apply { text = "뜀터"; textSize = 20f; gravity = Gravity.CENTER })
        metrics = TextView(this).apply { textSize = 18f; gravity = Gravity.CENTER }
        status = TextView(this).apply { text = "휴대전화에서 러닝을 시작해 주세요."; gravity = Gravity.CENTER }
        control = Button(this).apply { setOnClickListener { command() } }
        layout.addView(metrics); layout.addView(control); layout.addView(status)
        layout.addView(TextView(this).apply { text = "종료와 저장은 휴대전화에서 진행합니다."; gravity = Gravity.CENTER })
        setContentView(ScrollView(this).apply { addView(layout) })
    }
    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
        Wearable.getMessageClient(this).addListener(this)
        Wearable.getDataClient(this).dataItems.addOnSuccessListener { items ->
            try { for (item in items) accept(item) } finally { items.release() }
        }
        handler.post(tick)
    }
    override fun onPause() {
        handler.removeCallbacksAndMessages(null)
        pending = false
        requestId = null
        Wearable.getDataClient(this).removeListener(this)
        Wearable.getMessageClient(this).removeListener(this)
        super.onPause()
    }
    override fun onDataChanged(events: DataEventBuffer) { for (event in events) if (event.type == DataEvent.TYPE_CHANGED) accept(event.dataItem) }
    private fun accept(item: DataItem) {
        if (item.uri.path != "/runspot/state") return
        val value = try { JSONObject(DataMapItem.fromDataItem(item).dataMap.getString("json") ?: "{}") } catch (_: Exception) { return }
        if (value.optLong("updated") < state.optLong("updated")) return
        state = value; source = item.uri.host; render()
    }
    private fun render() {
        val fresh = System.currentTimeMillis() - state.optLong("updated") in 0..15000
        val phase = state.optString("state")
        val seconds = state.optInt("seconds")
        val pace = state.optInt("pace")
        metrics.text = String.format(Locale.KOREA, "%.2f km\n%02d:%02d\n%s", state.optDouble("distance", 0.0) / 1000, seconds / 60, seconds % 60,
            if (pace > 0) String.format(Locale.KOREA, "%d:%02d /km", pace / 60, pace % 60) else "페이스 측정 중")
        control.text = if (phase == "running") "일시정지" else "이어서 달리기"
        control.isEnabled = fresh && !pending && (phase == "running" || phase == "paused")
        if (!fresh) status.text = "연결 대기 중 · 휴대전화를 확인해 주세요."
    }
    private fun command() {
        val node = source ?: return
        val request = java.util.UUID.randomUUID().toString()
        requestId = request
        pending = true; render(); status.text = "요청 중"
        val body = JSONObject(mapOf("request" to request, "session" to state.optString("session"), "action" to if (state.optString("state") == "running") "pause" else "resume"))
        Wearable.getMessageClient(this).sendMessage(node, "/runspot/command", body.toString().toByteArray(Charsets.UTF_8))
            .addOnFailureListener { pending = false; status.text = "연결하지 못했습니다."; render() }
        handler.postDelayed({ if (pending && requestId == request) { pending = false; status.text = "응답이 없습니다. 휴대전화를 확인해 주세요."; render() } }, 10000)
    }
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/runspot/result" || event.sourceNodeId != source) return
        val result = try { JSONObject(String(event.data, Charsets.UTF_8)) } catch (_: Exception) { return }
        if (!pending || result.optString("request") != requestId) return
        val ok = result.optBoolean("ok")
        pending = false; status.text = if (ok) "요청을 반영했습니다." else "휴대전화에서 상태를 확인해 주세요."; render()
    }
}
