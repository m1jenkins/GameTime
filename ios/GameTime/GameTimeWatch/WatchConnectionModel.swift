import Observation
import SwiftUI
import WatchConnectivity

@MainActor
@Observable
final class WatchConnectionModel: NSObject {
    enum State: Equatable {
        case starting
        case waitingForPhone
        case setupReceived(lastUpdated: Date)
        case unavailable
    }

    private(set) var state: State = .starting

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    func activate() {
        guard let session else {
            state = .unavailable
            return
        }

        session.delegate = self
        if
            let handshake = GameTimeWatchContext.decode(
                session.receivedApplicationContext
            )
        {
            state = .setupReceived(lastUpdated: handshake.sentAt)
        }
        session.activate()
    }

    var title: String {
        switch state {
        case .starting:
            "Starting GameTime"
        case .waitingForPhone:
            "Waiting for iPhone"
        case .setupReceived:
            "iPhone setup received"
        case .unavailable:
            "Connection unavailable"
        }
    }

    var detail: String {
        switch state {
        case .starting:
            "Setting up the Watch connection."
        case .waitingForPhone:
            "Open GameTime on your iPhone once to finish connecting."
        case .setupReceived:
            "Your iPhone shared the connection setup. Challenge details come next."
        case .unavailable:
            "GameTime couldn’t start the Watch connection. "
                + "Reopen both apps and try again."
        }
    }

    var symbolName: String {
        switch state {
        case .starting:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .waitingForPhone:
            "iphone"
        case .setupReceived:
            "checkmark.circle.fill"
        case .unavailable:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch state {
        case .starting, .waitingForPhone:
            .orange
        case .setupReceived:
            .green
        case .unavailable:
            .red
        }
    }

    var lastUpdated: Date? {
        guard case .setupReceived(let date) = state else { return nil }
        return date
    }

    static var previewReady: WatchConnectionModel {
        let model = WatchConnectionModel()
        model.state = .setupReceived(
            lastUpdated: .now.addingTimeInterval(-90)
        )
        return model
    }
}

extension WatchConnectionModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else {
            Task { @MainActor [weak self] in
                self?.state = .unavailable
            }
            return
        }

        let handshake = GameTimeWatchContext.decode(
            session.receivedApplicationContext
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let handshake {
                state = .setupReceived(lastUpdated: handshake.sentAt)
            } else {
                state = .waitingForPhone
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard
            let handshake = GameTimeWatchContext.decode(applicationContext)
        else { return }

        Task { @MainActor [weak self] in
            self?.state = .setupReceived(lastUpdated: handshake.sentAt)
        }
    }
}
