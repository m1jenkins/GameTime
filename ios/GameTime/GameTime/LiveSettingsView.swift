import SwiftUI
import GameTimeCore

/// Account utilities stay behind You. These screens keep the existing service
/// operations and consent without routing into the retired app UI.
struct LiveSettingsView: View {
    let store: ChallengeV1Store
    @Environment(AppModel.self) private var model
    @Environment(PersonalAccountabilityStore.self) private var personalStore
    @Environment(\.demoMode) private var demoMode

    private var canOpenEarlierChallenges: Bool {
        guard let owner = personalStore.ownerID, owner == model.userID else { return false }
        if !personalStore.challenges.isEmpty || personalStore.pendingCancellation != nil
            || personalStore.hasPendingCancellationRecoveryIssue || personalStore.pendingCreation != nil
            || personalStore.hasPendingCreationRecoveryIssue { return true }
        // A failed load doesn't prove there is history, so the row stays hidden.
        switch personalStore.loadState {
        case .idle, .loading: return true
        case .loaded, .empty, .failed: return false
        }
    }

    var body: some View {
        LiveSettingsPage(title: "Settings") {
            VStack(spacing: 0) {
                NavigationLink { LiveHealthSettingsView(store: store) } label: {
                    LiveSettingsRow(symbol: "heart", title: "Apple Health", detail: "Activity and permissions")
                }
                Divider().padding(.leading, 52)
                NavigationLink { LivePrivacyView() } label: {
                    LiveSettingsRow(symbol: "lock", title: "Sharing & privacy", detail: "You choose what friends see")
                }
            }
            .modifier(LiveCardModifier(radius: 20, material: true))

            VStack(spacing: 0) {
                NavigationLink { LiveSimulationView() } label: {
                    LiveSettingsRow(symbol: "dollarsign.circle", title: "Simulated stakes", detail: "Amounts, fees and results")
                }
                Divider().padding(.leading, 52)
                NavigationLink { LiveSupportView() } label: {
                    LiveSettingsRow(symbol: "questionmark.circle", title: "Help & support", detail: "Get help and read our policies")
                }
                Divider().padding(.leading, 52)
                NavigationLink { LiveAccountView() } label: {
                    LiveSettingsRow(symbol: "person.crop.circle", title: "Account", detail: model.profile.map { "@\($0.handle)" } ?? "Sign-in and account deletion")
                }
                if canOpenEarlierChallenges {
                    Divider().padding(.leading, 52)
                    NavigationLink { LivePersonalHistoryView() } label: {
                        LiveSettingsRow(symbol: "clock.arrow.circlepath", title: "Earlier challenges", detail: "Your existing Personal agreements")
                    }
                    .accessibilityIdentifier("settings.personal-history")
                }
            }
            .modifier(LiveCardModifier(radius: 20, material: true))
            if demoMode.isActive {
                Button("Exit demo mode", action: demoMode.exit)
                    .buttonStyle(LivePrimaryButtonStyle())
                    .accessibilityIdentifier("demo.exit")
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LiveSettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    LiveRoundButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Text(title).font(.system(size: 25, weight: .bold)).tracking(-0.9)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 8)
                content
            }
            .padding(.horizontal, 24).padding(.top, 13).padding(.bottom, 24)
        }
        .background(SignalTheme.canvas.ignoresSafeArea())
        .foregroundStyle(SignalTheme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LiveSettingsRow: View {
    let symbol: String
    let title: String
    let detail: String
    var external = false

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(SignalTheme.textSecondary).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct LiveInformationCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.system(size: 17, weight: .semibold))
            content.font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiveCardModifier(radius: 20, material: true))
    }
}

private struct LiveHealthSettingsView: View {
    let store: ChallengeV1Store
    @Environment(AppModel.self) private var model
    @Environment(\.challengeHealthFlow) private var health
    @State private var working = false

    private var healthRows: [ChallengeV1] {
        store.challenges.filter { row in
            !row.isClosed && row.own(store.actor)?.exited == false && row.sourcePolicyVersion != nil
        }
    }

    var body: some View {
        LiveSettingsPage(title: "Apple Health") {
            LiveInformationCard(title: "Activity for your goals", symbol: "heart") {
                Text("Connect the activity needed for each goal. You can change GameTime’s access in Apple Health at any time.")
                if let profile = model.profile {
                    HStack {
                        Text("Time zone")
                        Spacer()
                        Text(SignalTimeZone.name(profile.timezone)).foregroundStyle(SignalTheme.textPrimary)
                    }
                    Text("Existing challenges keep their agreed dates and time zone.").font(.footnote)
                }
            }
            if let health, let actor = store.actor, health.actor == actor {
                ForEach(healthRows) { row in
                    if let binding = try? ChallengeHealthBindingMapper.agreement(row, actor: actor) {
                        activityCard(row, binding: binding, health: health)
                    }
                }
            }
            if healthRows.isEmpty || health == nil {
                LiveInformationCard(title: "Choose activity in a challenge", symbol: "figure.run") {
                    Text("Open a goal or create a challenge to connect its activity. We only ask for access when you choose to connect.")
                }
            }
            Button {
                working = true
                Task {
                    await store.refresh()
                    await health?.refresh()
                    working = false
                }
            } label: {
                Label(working ? "Refreshing…" : "Refresh activity", systemImage: "arrow.clockwise")
            }
            .buttonStyle(LivePrimaryButtonStyle()).disabled(working || store.refreshing)
            .accessibilityIdentifier("settings.health.refresh")
            Link("Manage access in Apple Health", destination: URL(string: "https://support.apple.com/en-us/HT204351")!)
                .font(.subheadline.weight(.semibold)).foregroundStyle(SignalTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func activityCard(_ row: ChallengeV1, binding: ChallengeHealthBinding, health: ChallengeHealthFlowStore) -> some View {
        let state = health.state(for: binding)
        return LiveInformationCard(title: LiveChallengePresentation.title(row), symbol: row.format.metric.symbol) {
            Text(ChallengeHealthCopy.title(state.readiness))
                .font(.subheadline.weight(.semibold)).foregroundStyle(SignalTheme.textPrimary)
            Text(ChallengeHealthCopy.explanation(state.readiness, timed: row.format.metric == .timed, readiness: false))
            if let message = state.message { Text(message).font(.footnote) }
            if state.readiness == .notConnected {
                Button("Connect Apple Health") {
                    working = true
                    Task {
                        await health.checkReadiness(binding, connect: true)
                        await health.refresh(row.id)
                        working = false
                    }
                }
                .buttonStyle(LivePrimaryButtonStyle()).disabled(working)
                .accessibilityIdentifier("settings.health.connect")
            }
        }
    }
}

private struct LivePrivacyView: View {
    var body: some View {
        LiveSettingsPage(title: "Sharing & privacy") {
            LiveInformationCard(title: "You choose what you share", symbol: "person.2") {
                Text("Your personal goals stay private. Selected friends can see the username, agreed goal, activity and result for your shared challenge.")
            }
            LiveInformationCard(title: "Only activity for your goal", symbol: "heart") {
                Text("With your permission, we read the Apple Health activity needed for the goal you choose. We send the scoring details needed for that challenge. We don’t share raw Health records or routes with friends.")
            }
            LiveInformationCard(title: "Missing activity isn’t a loss", symbol: "checkmark.shield") {
                Text("Missing data alone never proves a missed goal. Best-result challenges use their agreed scoring rules and deadline. Open any challenge to see its rules or ask for a review.")
            }
            LiveInformationCard(title: "Leave or get help", symbol: "hand.raised") {
                Text("Open a challenge to leave, report a problem or block an account. Account includes account deletion; Help & support includes your documents and support.")
            }
        }
    }
}

private struct LiveSimulationView: View {
    var body: some View {
        LiveSettingsPage(title: "Simulated stakes") {
            LiveInformationCard(title: "A practice amount", symbol: "dollarsign.circle") {
                Text("Stakes are simulated. No real money moves, and nothing can be paid out or redeemed.")
                HStack {
                    Text("Fee")
                    Spacer()
                    Text("$0").font(.headline).foregroundStyle(SignalTheme.textPrimary)
                }
            }
            LiveInformationCard(title: "Your agreement keeps its rules", symbol: "doc.text") {
                Text("Open a challenge’s Full rules to see its amount, possible outcomes and review options. A saved result and a recorded simulated return are separate updates.")
            }
        }
    }
}

private struct LiveSupportView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        LiveSettingsPage(title: "Help & support") {
            VStack(spacing: 0) {
                supportLink("Contact support", detail: "Tell us what happened", symbol: "envelope", url: model.configuration.supportMailtoURL)
                    .accessibilityIdentifier("account-support.contact")
                Divider().padding(.leading, 52)
                supportLink("Privacy Policy", detail: "How GameTime handles your data", symbol: "hand.raised", url: model.configuration.privacyPolicyURL)
                    .accessibilityIdentifier("account-support.privacy-policy")
                Divider().padding(.leading, 52)
                supportLink("Beta Terms", detail: "The terms for this beta release", symbol: "doc.text", url: model.configuration.betaTermsURL)
                    .accessibilityIdentifier("account-support.beta-terms")
            }
            .modifier(LiveCardModifier(radius: 20, material: true))
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
            Text("Version \(version)").font(.footnote).foregroundStyle(SignalTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func supportLink(_ title: String, detail: String, symbol: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) { LiveSettingsRow(symbol: symbol, title: title, detail: detail, external: true) }
        } else {
            LiveSettingsRow(symbol: symbol, title: title, detail: "This link isn’t available. Try again later.", external: true)
        }
    }
}

private struct LiveAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode
    @State private var confirmDeletion = false
    @State private var sheet: AccountSheet?

    private enum AccountSheet: String, Identifiable {
        case delete, receipt
        var id: Self { self }
    }

    var body: some View {
        LiveSettingsPage(title: "Account") {
            if let profile = model.profile {
                HStack(spacing: 12) {
                    LiveAvatar(username: profile.handle, actorID: profile.id, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName).font(.system(size: 18, weight: .semibold))
                        Text("@\(profile.handle)").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                    }
                }
                .padding(.bottom, 12)
            }
            if !demoMode.isActive {
                Button(model.isMutating ? "Signing out…" : "Sign out") {
                    SignalAccessibility.announce("Signing out…")
                    Task { await model.signOut() }
                }
                .buttonStyle(LivePrimaryButtonStyle()).disabled(model.isMutating)
                .accessibilityIdentifier("account-support.sign-out")
            }
            Button("Delete account") { confirmDeletion = true }
                .font(.subheadline.weight(.semibold)).foregroundStyle(SignalTheme.danger)
                .frame(maxWidth: .infinity, minHeight: 48)
                .disabled(model.isMutating || demoMode.isActive)
                .accessibilityIdentifier("account-support.delete")
            if model.accountDeletionReceipt != nil {
                Button("Check account deletion") { sheet = .receipt }
                    .buttonStyle(LivePrimaryButtonStyle())
                    .accessibilityIdentifier("account-support.deletion-receipt")
            }
        }
        .alert("Delete your account?", isPresented: $confirmDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) { sheet = .delete }
        } message: {
            Text("Deleting your GameTime account ends normal access to this Beta and your existing Personal account. We’ll stop new participation and sharing right away. We’ll remove account details and unneeded Beta drafts within seven days, while keeping what we need to finish results, reviews, and appeals. You can check a saved account-deletion receipt after signing out. This can’t be undone.")
        }
        .sheet(item: $sheet) { selected in
            if selected == .delete { LiveDeleteAccountView() }
            else { LiveAccountDeletionReceiptView() }
        }
    }
}

private struct LiveDeleteAccountView: View {
    private enum DeletionState: Equatable { case confirm, deleting, failed(String) }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var state = DeletionState.confirm

    var body: some View {
        NavigationStack {
            LiveSettingsPage(title: "Delete account") {
                switch state {
                case .confirm:
                    LiveInformationCard(title: "Confirm with Apple", symbol: "person.crop.circle.badge.minus") {
                        Text("Deleting your GameTime account ends normal access to this Beta and your existing Personal account. We’ll stop new challenges and sharing right away. We keep the small set of records needed to finish results and reviews.")
                        Text("Apple asks you to confirm before we start. You can check the saved account-deletion receipt after signing out.")
                    }
                    LiveAccountAppleConfirmation(completion: confirm)
                case .deleting:
                    LiveInformationCard(title: "Saving your account deletion…", symbol: "clock") {
                        ProgressView()
                        Text("We’re ending normal access and clearing saved account data from this phone.")
                    }
                case .failed(let message):
                    LiveInformationCard(title: "Deletion didn’t finish", symbol: "exclamationmark.circle") {
                        Text(message)
                        Button("Try again") { state = .confirm }.buttonStyle(LivePrimaryButtonStyle())
                        if let url = model.configuration.supportMailtoURL {
                            Link("Contact support", destination: url).foregroundStyle(SignalTheme.accent)
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
            .disabled(state == .deleting)
        }
        .interactiveDismissDisabled(state == .deleting)
    }

    private func confirm(_ result: Result<AppleIdentity, Error>) {
        switch result {
        case .failure(let error):
            state = .failed(error.localizedDescription)
            SignalAccessibility.announce("Account deletion failed.")
        case .success(let identity):
            state = .deleting
            SignalAccessibility.announce("Deleting your account…")
            Task {
                do {
                    _ = try await model.deleteAccount(with: identity)
                    SignalAccessibility.announce("Account deletion saved.")
                    dismiss()
                } catch is CancellationError {
                    state = .confirm
                } catch {
                    state = .failed(error.localizedDescription)
                    SignalAccessibility.announce("Account deletion failed.")
                }
            }
        }
    }
}

private struct LiveAccountAppleConfirmation: View {
    let completion: (Result<AppleIdentity, Error>) -> Void
    var body: some View {
        #if DEBUG
        if let code = ChallengeLocalAccountDeletionLaunch.confirmationCode {
            Button("Confirm local test account") {
                completion(.success(AppleIdentity(idToken: "local-account-deletion-confirmation", rawNonce: "local-account-deletion-confirmation", firstSignInDisplayName: nil, authorizationCode: code)))
            }
            .buttonStyle(LivePrimaryButtonStyle())
            .accessibilityIdentifier("account-deletion.local-confirm")
        } else {
            NativeAppleReauthenticationButton(completion: completion)
        }
        #else
        NativeAppleReauthenticationButton(completion: completion)
        #endif
    }
}

/// Also available after sign-out so account closure never removes the saved
/// route to outstanding review, appeal, or Apple confirmation rights.
struct LiveAccountDeletionReceiptView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var isWorking = false
    @State private var reviewReason = "wrong_total"

    var body: some View {
        NavigationStack {
            LiveSettingsPage(title: "Account deletion") {
                if let status = model.accountDeletionStatus {
                    receipt(status)
                } else if let error = model.accountDeletionStatusError {
                    LiveInformationCard(title: "We couldn’t load your receipt", symbol: "exclamationmark.circle") {
                        Text(error)
                        Button("Try again") { Task { await model.refreshAccountDeletionStatus() } }
                            .buttonStyle(LivePrimaryButtonStyle())
                    }
                } else {
                    ProgressView("Checking your account deletion…")
                }
                if let message { Text(message).font(.subheadline).foregroundStyle(SignalTheme.textSecondary) }
            }
        }
        .task { await model.refreshAccountDeletionStatus() }
    }

    @ViewBuilder private func receipt(_ status: AccountDeletionStatus) -> some View {
        LiveInformationCard(title: statusTitle(status), symbol: "checkmark.shield") {
            switch status.state {
            case .pendingProvider:
                Text("Confirm with Apple again so we can finish account closure. Your saved receipt keeps this as the same request.")
                LiveAccountAppleConfirmation { result in
                    guard case let .success(identity) = result else {
                        message = "We couldn’t get Apple confirmation. Try again."
                        return
                    }
                    perform {
                        _ = try await model.resumeAccountDeletion(with: identity)
                        await model.refreshAccountDeletionStatus()
                    }
                }.disabled(isWorking)
            case .pendingAccountClose:
                Text("Apple confirmation is complete. We can finish closing the account now.")
                Button("Finish account closure") {
                    perform {
                        _ = try await model.resumeAccountDeletion(with: nil)
                        await model.refreshAccountDeletionStatus()
                    }
                }.buttonStyle(LivePrimaryButtonStyle()).disabled(isWorking)
            case .held:
                Text("A review or appeal is still open. We keep only the records needed to finish it.")
            case .completed:
                Text("Normal sign-in and new participation are closed.")
            }
            if let closed = status.accountClosedAt {
                Text("Account access closed \(AccountDeletionReceiptDate.display(closed)).").font(.footnote)
            }
            if let expires = status.receiptExpiresAt {
                Text("Receipt available until \(AccountDeletionReceiptDate.display(expires)).").font(.footnote)
            }
        }
        if !status.retained.isEmpty {
            LiveInformationCard(title: "What we still keep", symbol: "doc.text") {
                ForEach(status.retained) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.category.capitalized).font(.subheadline.weight(.semibold))
                        if let completed = record.completedAt {
                            Text("Finished \(AccountDeletionReceiptDate.display(completed)).").font(.footnote)
                        } else if let until = record.until {
                            Text("Kept until \(AccountDeletionReceiptDate.display(until)).").font(.footnote)
                        }
                    }
                }
            }
        }
        if model.hasPendingAccountDeletionRightsRequest {
            LiveInformationCard(title: "Your saved request", symbol: "clock") {
                Text("A saved review or appeal request still needs a response from us.")
                Button("Retry saved request") {
                    perform {
                        try await model.retryPendingAccountDeletionRightsRequest()
                        message = "We saved your request."
                    }
                }.buttonStyle(LivePrimaryButtonStyle()).disabled(isWorking)
            }
        }
        if let rights = status.rights {
            ForEach(rights.reviewNotices) { notice in
                LiveInformationCard(title: "Review your result", symbol: "checkmark.bubble") {
                    Text("Ask us to review this result by \(AccountDeletionReceiptDate.display(notice.reviewBy)).")
                    Picker("Reason", selection: $reviewReason) {
                        Text("My total looks wrong").tag("wrong_total")
                        Text("Activity is missing").tag("missing_activity")
                        Text("My result looks wrong").tag("wrong_result")
                    }.pickerStyle(.menu)
                    Button("Ask us to review") {
                        perform {
                            try await model.fileAccountDeletionReview(notice: notice, reason: reviewReason)
                            message = "We saved your review request."
                        }
                    }.buttonStyle(LivePrimaryButtonStyle()).disabled(isWorking)
                }
            }
            if rights.appealAvailable {
                LiveInformationCard(title: "Ask for an appeal", symbol: "person.crop.circle.badge.questionmark") {
                    Text("You can ask for an independent appeal of the account decision.")
                    Button("Ask for an appeal") {
                        perform {
                            try await model.fileAccountDeletionAppeal()
                            message = "We saved your appeal request."
                        }
                    }.buttonStyle(LivePrimaryButtonStyle()).disabled(isWorking)
                }
            }
            if rights.holdsReviewDue {
                Text("We will check the open review or appeal every 30 days. It stays open until the assigned decision is complete.")
                    .font(.footnote).foregroundStyle(SignalTheme.textSecondary)
            }
        }
    }

    private func statusTitle(_ status: AccountDeletionStatus) -> String {
        switch status.state {
        case .pendingProvider: "We stopped normal account access"
        case .pendingAccountClose: "Finishing account closure"
        case .held: "Account access is closed"
        case .completed: "Account closure is complete"
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do { try await operation() }
            catch { message = error.localizedDescription }
        }
    }
}
