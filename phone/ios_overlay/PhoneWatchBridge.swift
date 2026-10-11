import Flutter
import Foundation
import WatchConnectivity

/// iPhone side of the Apple Watch link. Forwards a watch SOS to Flutter,
/// which then opens a pre-filled SMS composer (iOS never allows silent SMS).
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    private var channel: FlutterMethodChannel?

    /// Call once from AppDelegate after the Flutter engine exists:
    ///   PhoneWatchBridge.shared.start(messenger: <FlutterBinaryMessenger>)
    func start(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "safety/native", binaryMessenger: messenger)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func forwardSOS() {
        DispatchQueue.main.async { self.channel?.invokeMethod("watchSos", arguments: nil) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        if message["sos"] as? Bool == true { forwardSOS() }
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["sos"] as? Bool == true { forwardSOS() }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
