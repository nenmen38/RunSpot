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
                "기록 꾸미기에서 케이던스를 추가하면 러닝 구간의 걸음 수를 읽어 분당 평균을 계산합니다. 공유 이미지에는 직접 선택한 지표만 포함합니다. 외부 기록 가져오기는 운동 조회에 필요한 거리·걸음·총 칼로리 권한도 요청합니다. 최근 30일 달리기를 읽고 선택한 날짜·거리·시간만 본인 계정에 저장합니다.\n\n" +
                "케이던스 계산은 기기 안에서 이루어지며 걸음 수 원본은 공유 이미지에 담지 않습니다. " +
                "건강 데이터의 보관과 삭제는 원래 자료를 저장한 건강 앱에서 관리합니다.\n\n" +
                "본인 기기의 자료인지 확인해 주세요. 헬스 커넥트의 앱 권한에서 런스팟의 읽기 허용을 언제든 해제할 수 있습니다. " +
                "접근을 허용하지 않아도 개인 러닝 측정과 기록은 사용할 수 있습니다."
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
