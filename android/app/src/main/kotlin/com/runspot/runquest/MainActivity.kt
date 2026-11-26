package com.runspot.runquest

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var watchBridge: WatchBridge? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        watchBridge?.close()
        watchBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        watchBridge = WatchBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runspot/run_notification")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    updateRunNotification(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // 홈 화면 위젯에 이번 주 기록을 넘깁니다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runspot/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    RunWidgetProvider.save(
                        this,
                        call.argument<String>("weekKm") ?: "0.0",
                        call.argument<Int>("goalKm") ?: 0,
                        call.argument<Int>("percent") ?: 0,
                        call.argument<Int>("runs") ?: 0,
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * 러닝 측정 알림(위치 측정 서비스가 띄운 알림)의 내용을 거리·시간·페이스로 바꿉니다.
     * 측정 알림이 떠 있을 때만 바꿔, 러닝이 끝난 뒤 알림이 남지 않게 합니다.
     */
    private fun updateRunNotification(title: String, text: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.activeNotifications.none { it.id == RUN_NOTIFICATION_ID }) return
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            setPackage(null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }
        val content = launch?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = Notification.Builder(this, RUN_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_footprints)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(content)
            .build()
        manager.notify(RUN_NOTIFICATION_ID, notification)
    }

    companion object {
        // geolocator 플러그인의 위치 측정 알림 번호와 채널입니다. 같은 알림을 고쳐 씁니다.
        private const val RUN_NOTIFICATION_ID = 75415
        private const val RUN_CHANNEL_ID = "geolocator_channel_01"
    }
}
