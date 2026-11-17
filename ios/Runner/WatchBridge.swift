import Flutter
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
  private let channel: FlutterMethodChannel
  private var latest: [String: Any] = [:]
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "runspot/watch", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "state", let state = call.arguments as? [String: Any] else { result(FlutterMethodNotImplemented); return }
      self?.latest = state
      self?.publish()
      result(nil)
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }
  private func publish() {
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
    do { try session.updateApplicationContext(latest) } catch { return }
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.publish() }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async {
      self.channel.invokeMethod("command", arguments: message) { result in
        replyHandler(["ok": result as? Bool ?? false])
      }
    }
  }
}
