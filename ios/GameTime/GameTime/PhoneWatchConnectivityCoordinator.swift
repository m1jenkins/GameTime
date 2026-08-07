import WatchConnectivity
import os

final class PhoneWatchConnectivityCoordinator: NSObject {
    private let session: WCSession?
    private let logger = Logger(
        subsystem: "com.mjenkins.gametime",
        category: "WatchConnectivity"
    )

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    private func publishReady(using session: WCSession) {
        do {
            try session.updateApplicationContext(GameTimeWatchContext.ready())
        } catch {
            logger.error("Unable to publish the Watch setup handshake.")
        }
    }
}

extension PhoneWatchConnectivityCoordinator: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else { return }
        publishReady(using: session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.activationState == .activated else { return }
        publishReady(using: session)
    }
}
