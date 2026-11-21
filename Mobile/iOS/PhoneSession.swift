import Foundation
import WatchConnectivity

/// Passes each new snapshot on to the Apple Watch.
final class PhoneSession: NSObject, WCSessionDelegate {
    static let shared = PhoneSession()
    private var pending: Data?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ data: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = data
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        // The context always holds the latest state; the complication transfer wakes the watch face sooner.
        try? session.updateApplicationContext(["snapshot": data])
        if session.isComplicationEnabled {
            session.transferCurrentComplicationUserInfo(["snapshot": data])
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let data = pending {
            pending = nil
            send(data)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
