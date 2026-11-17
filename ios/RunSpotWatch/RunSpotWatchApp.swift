import SwiftUI
import WatchConnectivity

@main
struct RunSpotWatchApp: App {
  @StateObject private var link = PhoneLink()
  var body: some Scene { WindowGroup { RunView(link: link) } }
}
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
  @Published var state: [String: Any] = [:]
  @Published var message = "휴대전화에서 러닝을 시작해 주세요."
  @Published var sending = false
  override init() {
    super.init()
    WCSession.default.delegate = self
    WCSession.default.activate()
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    receive(session.receivedApplicationContext)
  }
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
  private func receive(_ data: [String: Any]) {
    DispatchQueue.main.async { self.state = data }
  }
  func command(_ action: String) {
    guard WCSession.default.isReachable, !sending else { message = "휴대전화 앱 연결을 확인해 주세요."; return }
    sending = true
    WCSession.default.sendMessage(["action": action, "session": state["session"] as? String ?? ""], replyHandler: { reply in
      DispatchQueue.main.async { self.sending = false; self.message = reply["ok"] as? Bool == true ? "요청을 반영했습니다." : "휴대전화에서 상태를 확인해 주세요." }
    }, errorHandler: { _ in DispatchQueue.main.async { self.sending = false; self.message = "연결하지 못했습니다. 다시 시도해 주세요." } })
  }
}
struct RunView: View {
  @ObservedObject var link: PhoneLink
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let updated = (link.state["updated"] as? Double ?? 0) / 1000
      let fresh = timeline.date.timeIntervalSince1970 - updated < 15
      let running = link.state["state"] as? String == "running"
      let paused = link.state["state"] as? String == "paused"
      let seconds = link.state["seconds"] as? Int ?? 0
      let pace = link.state["pace"] as? Int ?? 0
      ScrollView {
        VStack(spacing: 8) {
          Text("런스팟").font(.headline)
          Text(fresh ? (running ? "달리는 중" : paused ? "일시정지" : "휴대전화에서 시작") : "연결 대기 중").foregroundStyle(.secondary)
          Text(String(format: "%.2f km", (link.state["distance"] as? Double ?? 0) / 1000)).font(.title2)
          Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
          Text(pace > 0 ? String(format: "%d:%02d /km", pace / 60, pace % 60) : "페이스 측정 중")
          if running || paused {
            Button(running ? "일시정지" : "이어서 달리기") { link.command(running ? "pause" : "resume") }.disabled(!fresh || link.sending)
          }
          Text(link.message).font(.footnote)
          Text("종료와 저장은 휴대전화에서 진행합니다.").font(.footnote).foregroundStyle(.secondary)
        }.padding()
      }
    }
  }
}
