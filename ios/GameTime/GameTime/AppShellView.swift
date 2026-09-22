import SwiftUI

/// Compatibility entry point; the retired Personal tab shell is not mounted.
struct AppShellView: View {
    var body: some View { SignalProductShell() }
}

struct AppShellForegroundRefreshGate {
    private var hasEnteredBackground = false

    mutating func shouldRefresh(after phase: ScenePhase) -> Bool {
        if phase == .background {
            hasEnteredBackground = true
            return false
        }
        guard phase == .active, hasEnteredBackground else { return false }
        hasEnteredBackground = false
        return true
    }
}

struct AppAccountNavigationView: View {
    var challengeStore: ChallengeV1Store? = nil
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationStack { LiveSettingsView(store: challengeStore ?? model.challengesV1) }
    }
}

struct SignalChallengeUnavailableView: View {
    var body: some View {
        LiveUnavailableSheet(title: "New challenges aren’t open yet",
                             message: "Refresh your saved challenges or return later.")
    }
}

/// The same native mockup-derived shell for ordinary sign-in, private trials,
/// and fixtures. Configuration still controls actual admission and services.
struct SignalProductShell: View {
    @Environment(AppModel.self) private var model
    private var serviceAvailable: Bool {
        #if DEBUG
        if LiveDesignFixtures.enabled { return true }
        #endif
        return model.configuration.challengeV1RuntimeEnabled
    }
    var body: some View {
        LiveChallengeShell(store: model.challengesV1, invitation: model.challengeInvitation,
                           logout: { await model.signOut() }, profile: model.profile, accountActor: model.userID,
                           accountContent: AnyView(LiveSettingsView(store: model.challengesV1)),
                           serviceAvailable: serviceAvailable,
                           personalStepsOnly: model.configuration.privateHealthAccountMode)
            .environment(\.challengeHealthFlow, model.challengeHealth)
            .modifier(LivePersonalRouteBridge())
            .task(id: model.userID) {
                if model.challengesV1.actor != model.userID { model.challengesV1.setActor(model.userID) }
                await model.challengesV1.refresh()
                await model.challengeHealth?.refresh()
            }
    }
}
