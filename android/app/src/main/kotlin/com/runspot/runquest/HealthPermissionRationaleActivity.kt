package com.runspot.runquest

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

// 운영체제의 건강 권한 화면에서 열리는 데이터 이용 안내입니다.
class HealthPermissionRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "건강 데이터 이용 안내"
        val text = TextView(this).apply {
            textSize = 18f
            val inset = (24 * resources.displayMetrics.density).toInt()
            setPadding(inset, inset, inset, inset)
            text = "런스팟 건강 데이터 이용 안내\n\n" +
                "사용자가 요청한 러닝의 시작부터 종료까지 심박수와 활동 칼로리를 읽어 표시합니다. " +
                "일시 정지 시간도 포함하며 직접 입력한 자료는 제외합니다.\n\n" +
                "읽기만 요청하며 건강 데이터를 작성·삭제하거나 백그라운드에서 조회하지 않습니다. " +
                "건강 데이터는 서버·친구·광고 서비스에 전송하거나 기록·공유 이미지에 저장하지 않습니다.\n\n" +
                "조회 결과는 해당 화면에서만 사용하며 화면 종료 또는 백그라운드 전환 때 해제합니다. " +
                "건강 데이터의 보관과 삭제는 원래 자료를 저장한 건강 앱에서 관리합니다.\n\n" +
                "본인 기기의 자료인지 확인해 주세요. 헬스 커넥트의 앱 권한에서 런스팟의 읽기 허용을 언제든 해제할 수 있습니다. " +
                "접근을 허용하지 않아도 개인 러닝 측정과 기록은 사용할 수 있습니다."
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
