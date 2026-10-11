import Foundation
import WatchConnectivity
import WatchKit

/// Talks to the paired iPhone over Bluetooth via WatchConnectivity.
/// No internet is needed on either device for this link.
final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status: String = "Hold to send SOS"

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendSOS() {
        WKInterfaceDevice.current().play(.notification)
        let payload: [String: Any] = ["sos": true, "t": Date().timeIntervalSince1970]
        let session = WCSession.default

        if session.activationState == .activated && session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] _ in
                DispatchQueue.main.async { self?.status = "Phone received SOS" }
            }, errorHandler: { [weak self] _ in
                self?.queue(payload)
            })
            status = "Sending..."
        } else {
            queue(payload)
        }
    }

    /// transferUserInfo is queued by the OS and delivered as soon as the
    /// phone is reachable again, even if the watch app is closed.
    private func queue(_ payload: [String: Any]) {
        WCSession.default.transferUserInfo(payload)
        DispatchQueue.main.async { self.status = "Phone not reachable - queued" }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
