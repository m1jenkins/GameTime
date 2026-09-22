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
    /// The server reports what this account may create. A server from before
    /// that report keeps the private trial's two pairs for its enrolled build.
    private var allowedPolicies: Set<String>? {
        if let availability = model.challengesV1.availability { return availability.creatablePolicies }
        return model.configuration.privateHealthAccountMode ? ChallengeV1Availability.privateTrialPolicies : nil
    }
    var body: some View {
        LiveChallengeShell(store: model.challengesV1, invitation: model.challengeInvitation,
                           logout: { await model.signOut() }, profile: model.profile, accountActor: model.userID,
                           accountContent: AnyView(LiveSettingsView(store: model.challengesV1)),
                           serviceAvailable: serviceAvailable,
                           allowedPolicies: allowedPolicies)
            .environment(\.challengeHealthFlow, model.challengeHealth)
            .environment(serviceAvailable ? model.friends : nil)
            .modifier(LivePersonalRouteBridge())
            .task(id: model.userID) {
                if model.challengesV1.actor != model.userID { model.challengesV1.setActor(model.userID) }
                if model.friends.actor != model.userID { model.friends.setActor(model.userID) }
                await model.challengesV1.refresh()
                await model.saveOnboardingAgeConfirmation()
                if serviceAvailable { await model.friends.refresh() }
                await model.challengeHealth?.refresh()
            }
    }
}
