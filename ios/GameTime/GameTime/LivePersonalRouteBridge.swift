import SwiftUI
import Observation
import UIKit

/// A route waits for the shell's own sheet dismissal before it is presented.
/// The final UIKit check also covers a detail-owned sheet (for example a
/// participant) which the shell does not own. The intent stays queued until
/// that sheet closes; no arbitrary delay or discarded navigation is needed.
@MainActor @Observable final class LivePersonalRouteCoordinator {
    fileprivate struct Request {
        let id = UUID()
        let owner: UUID
        let challenge: UUID
    }
    fileprivate var request: Request?
    fileprivate var readyRequestID: UUID?
    @ObservationIgnored private var presentationTask: Task<Void, Never>?
    var pendingID: UUID? { request?.id }

    fileprivate func begin(owner: UUID, challenge: UUID) {
        cancel()
        request = Request(owner: owner, challenge: challenge)
    }

    func allowPresentation() {
        guard let id = pendingID, presentationTask == nil else { return }
        presentationTask = Task { @MainActor in
            while !Task.isCancelled, request?.id == id {
                let activeWindow = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }
                    .flatMap(\.windows).first(where: \.isKeyWindow)
                if let root = activeWindow?.rootViewController, root.presentedViewController == nil {
                    readyRequestID = id
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
        }
    }

    fileprivate func cancel() {
        presentationTask?.cancel()
        presentationTask = nil
        request = nil
        readyRequestID = nil
    }
}

private struct LivePersonalRouteCoordinatorKey: EnvironmentKey {
    static let defaultValue: LivePersonalRouteCoordinator? = nil
}

extension EnvironmentValues {
    var livePersonalRouteCoordinator: LivePersonalRouteCoordinator? {
        get { self[LivePersonalRouteCoordinatorKey.self] }
        set { self[LivePersonalRouteCoordinatorKey.self] = newValue }
    }
}

/// Existing Personal navigation intents open the replacement UI. This bridge
/// does not enable dormant push categories, contest routes, or old creation.
struct LivePersonalRouteBridge: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(AppModel.self) private var model
    @Environment(PersonalAccountabilityStore.self) private var personalStore
    @State private var destination: PersonalDestination?
    @State private var coordinator = LivePersonalRouteCoordinator()

    private struct PersonalDestination: Identifiable {
        let owner: UUID
        let challenge: UUID
        var id: UUID { challenge }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.livePersonalRouteCoordinator, coordinator)
            .sheet(item: $destination) { destination in
                NavigationStack {
                    if model.userID == destination.owner && personalStore.ownerID == destination.owner {
                        LivePersonalDetailView(challengeID: destination.challenge)
                    }
                }
                .tint(SignalTheme.accent).preferredColorScheme(.light)
                .presentationDragIndicator(.visible)
            }
            .onAppear(perform: receiveRoute)
            .onChange(of: router.challengesPath) { receiveRoute() }
            .onChange(of: router.todayPath) { receiveRoute() }
            .onChange(of: coordinator.readyRequestID) { _, id in
                guard let request = coordinator.request, id == request.id,
                      model.userID == request.owner, personalStore.ownerID == request.owner else { return }
                destination = PersonalDestination(owner: request.owner, challenge: request.challenge)
                coordinator.cancel()
            }
            .onChange(of: personalStore.ownerID) { _, owner in
                if destination?.owner != owner { destination = nil }
                if coordinator.request?.owner != owner { coordinator.cancel() }
                receiveRoute()
            }
            .onChange(of: model.userID) { _, owner in
                if destination?.owner != owner { destination = nil }
                if coordinator.request?.owner != owner { coordinator.cancel() }
                receiveRoute()
            }
            .onDisappear { if model.phase != .signedIn { coordinator.cancel() } }
    }

    private func receiveRoute() {
        guard model.phase == .signedIn, let owner = model.userID,
              personalStore.ownerID == owner else { return }
        let challengeRoute = router.challengesPath.compactMap { route -> UUID? in
            if case .personalChallenge(let id) = route { return id }
            return nil
        }.last
        let todayRoute = router.todayPath.compactMap { route -> UUID? in
            if case .personalChallenge(let id) = route { return id }
            return nil
        }.last
        guard let id = router.selectedTab == .today ? todayRoute ?? challengeRoute : challengeRoute ?? todayRoute else { return }
        destination = nil
        coordinator.begin(owner: owner, challenge: id)
        router.presentedSheet = nil
        router.challengesPath.removeAll { if case .personalChallenge = $0 { return true }; return false }
        router.todayPath.removeAll { if case .personalChallenge = $0 { return true }; return false }
    }
}
