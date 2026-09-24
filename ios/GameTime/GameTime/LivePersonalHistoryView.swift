import SwiftUI

/// Existing Personal agreements retain their original services and terms.
/// Only their presentation is replaced; this route cannot create an agreement.
struct LivePersonalHistoryView: View {
    @Environment(PersonalAccountabilityStore.self) private var store

    var body: some View {
        LivePersonalPage(title: "Earlier challenges") {
            Text("Your existing Personal agreements keep the rules you accepted.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            LivePersonalCreationRecovery()
            LivePersonalCancellationRecovery(challengeID: nil)
            ForEach(store.challenges) { challenge in
                NavigationLink {
                    LivePersonalDetailView(challengeID: challenge.id)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(LivePersonalCopy.title(challenge.terms))
                                .liveFont(19, weight: .bold).tracking(-0.6)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.system(size: 12))
                                .foregroundStyle(SignalTheme.textSecondary)
                        }
                        Text(LivePersonalCopy.dates(challenge.terms))
                            .liveFont(12).foregroundStyle(SignalTheme.textSecondary)
                        LiveStateChip(text: LivePersonalCopy.state(challenge.presentationStatus(at: Date()), outcome: challenge.outcome),
                                      warning: challenge.outcome?.kind == .missedGoal,
                                      neutral: challenge.outcome == nil || challenge.outcome?.kind == .inconclusive)
                        if let progress = store.displayedProgress(for: challenge) {
                            LiveMetric(value: LivePersonalCopy.steps(progress, terms: challenge.terms).formatted(), unit: "steps", size: 58)
                            Text(PersonalProgressPresentation(progress: progress, terms: challenge.terms).stepsText)
                                .font(.caption).foregroundStyle(SignalTheme.textSecondary)
                        }
                        Text(challenge.terms.targetText).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(LiveCardModifier())
                }
                .buttonStyle(.plain)
            }
            if store.challenges.isEmpty {
                Text("No earlier challenges are available. Refresh to check again.")
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            }
            Button("Refresh") { Task { await store.refresh() } }
                .buttonStyle(LiveSecondaryButtonStyle())
            if let error = store.presentedError {
                Text(error).font(.footnote).foregroundStyle(SignalTheme.textSecondary)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }
}

/// Only replays an already-submitted, saved request. An unsubmitted old draft
/// can be removed, but this recovery screen never offers fresh creation.
private struct LivePersonalCreationRecovery: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @State private var working = false
    @State private var confirmRemoval = false
    @State private var restoredChallenge: UUID?

    var body: some View {
        Group {
            if store.hasPendingCreationRecoveryIssue {
                LivePersonalCard(title: "Check your saved draft", symbol: "doc.badge.clock") {
                    Text("We couldn’t read the draft saved on this phone. Try again to check what happened.")
                    Button(working ? "Checking…" : "Check saved draft") {
                        working = true
                        Task {
                            await store.retryPendingCreationRecovery()
                            await store.refresh()
                            working = false
                        }
                    }
                    .buttonStyle(LiveSecondaryButtonStyle()).disabled(working || store.isMutating)
                    .accessibilityIdentifier("personal.creation.recovery")
                }
            }
            if let pending = store.pendingCreation, pending.ownerID == store.ownerID {
                LivePersonalCard(title: pending.attemptCount > 0 ? "Your saved challenge" : "Unfinished draft", symbol: "doc.text") {
                    Text("\(pending.request.targetSteps.formatted()) steps · \(pending.request.cadence.title)")
                        .font(.headline).foregroundStyle(SignalTheme.textPrimary)
                    Text(PersonalCommitmentProtectionPresentation(amountMinor: pending.request.commitmentAmountMinor,
                        settlementMode: store.configuration.personalSettlementMode).text)
                    if pending.attemptCount > 0 {
                        Text("We haven’t confirmed the challenge you already submitted. Try again with the same saved request.")
                        if !store.healthReadiness.permitsCreation {
                            Button(store.isVerifyingHealthAccess ? "Connecting…" : "Connect Apple Health") {
                                Task { _ = await store.verifyHealthAccess(timezone: pending.request.timezone) }
                            }
                            .buttonStyle(LiveSecondaryButtonStyle())
                            .disabled(store.isVerifyingHealthAccess || !store.configuration.activitySyncEnabled)
                        }
                        Button(working ? "Checking your challenge…" : "Retry saved challenge") {
                            retry(pending)
                        }
                        .buttonStyle(LivePrimaryButtonStyle())
                        .disabled(working || store.isMutating || store.hasPendingCreationRecoveryIssue
                                  || !store.healthReadiness.permitsCreation)
                        .accessibilityIdentifier("personal.creation.retry")
                    } else {
                        Text("This draft was never submitted. You can remove it without cancelling a challenge.")
                        Button("Remove draft") { confirmRemoval = true }
                            .buttonStyle(LiveSecondaryButtonStyle(warning: true))
                            .disabled(working || store.isMutating || store.hasPendingCreationRecoveryIssue)
                    }
                }
            }
            if let restoredChallenge {
                NavigationLink { LivePersonalDetailView(challengeID: restoredChallenge) } label: {
                    Label("Open saved challenge", systemImage: "arrow.right")
                }
                .buttonStyle(LivePrimaryButtonStyle())
            }
        }
        .alert("Remove this draft?", isPresented: $confirmRemoval) {
            Button("Keep draft", role: .cancel) {}
            Button("Remove draft", role: .destructive) {
                guard store.pendingCreation?.attemptCount == 0 else { return }
                working = true
                Task {
                    _ = await store.discardPendingCreation()
                    working = false
                }
            }
        } message: {
            Text("This removes the unsubmitted draft from your phone. Existing challenges keep their rules.")
        }
        .onChange(of: store.ownerID) { _, _ in
            restoredChallenge = nil
            working = false
            confirmRemoval = false
        }
    }

    private func retry(_ pending: PendingPersonalChallengeSubmission) {
        guard !working, pending.attemptCount > 0, pending.ownerID == store.ownerID else { return }
        working = true
        Task {
            defer { working = false }
            await store.refresh()
            guard store.ownerID == pending.ownerID, store.pendingCreation?.request == pending.request,
                  !store.hasPendingCreationRecoveryIssue else { return }
            restoredChallenge = await store.create(pending.request)
        }
    }
}

struct LivePersonalDetailView: View {
    let challengeID: UUID
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmCancellation = false
    @State private var working = false
    @State private var message: String?

    private var challenge: PersonalChallengeDetail? { store.detail(for: challengeID) }

    var body: some View {
        LivePersonalPage(title: challenge.map { LivePersonalCopy.title($0.terms) } ?? "Your challenge") {
            if let challenge {
                hero(challenge)
                if let outcome = challenge.outcome {
                    let result = PersonalResultPresentation(terms: challenge.terms, outcome: outcome)
                    LivePersonalCard(title: "Result", symbol: "checkmark.shield") {
                        Text(result.title).font(.headline).foregroundStyle(SignalTheme.textPrimary)
                        ForEach(result.details, id: \.self) { Text($0) }
                    }
                    .accessibilityIdentifier("personal.result")
                }
                if challenge.terms.settlementMode == .stripeSandbox {
                    LivePersonalPaymentCard(challenge: challenge)
                }
                health(challenge)
                rules(challenge)
                days(challenge)
                LivePersonalCancellationRecovery(challengeID: challengeID)
                if canCancel(challenge) {
                    Button("Cancel this challenge") { confirmCancellation = true }
                        .buttonStyle(LiveSecondaryButtonStyle(warning: true))
                        .disabled(working || store.isMutating)
                        .accessibilityIdentifier("personal.cancel")
                }
            } else {
                ProgressView("Loading your challenge…").frame(maxWidth: .infinity)
                Button("Try again") { Task { await store.openDetail(challengeID: challengeID) } }
                    .buttonStyle(LiveSecondaryButtonStyle())
            }
            if let message { Text(message).font(.footnote).foregroundStyle(SignalTheme.textSecondary) }
            if let error = store.presentedError {
                Text(error).font(.footnote).foregroundStyle(SignalTheme.textSecondary)
            }
            if let url = model.configuration.supportMailtoURL {
                Link("Contact support", destination: url)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(SignalTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .task(id: challengeID) { await store.openDetail(challengeID: challengeID) }
        .refreshable { await refresh() }
        .alert("Cancel this challenge?", isPresented: $confirmCancellation) {
            Button("Keep it", role: .cancel) {}
            Button("Yes, cancel it", role: .destructive) {
                working = true
                Task {
                    let succeeded = await store.cancel(challengeID: challengeID)
                    message = succeeded ? "Cancellation confirmed." : "Cancellation is saved, but it is not confirmed yet."
                    PersonalAccessibilityAnnouncements.post(message ?? "")
                    working = false
                }
            }
        } message: { Text(cancellationMessage) }
    }

    private func hero(_ challenge: PersonalChallengeDetail) -> some View {
        let progress = store.displayedProgress(for: challenge)
        return VStack(alignment: .leading, spacing: 12) {
            (dynamicTypeSize.isAccessibilitySize
                      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                      : AnyLayout(HStackLayout(alignment: .top))) {
                Text(challenge.terms.targetText).liveFont(14, weight: .medium)
                    .foregroundStyle(SignalTheme.textSecondary)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                LiveStateChip(text: LivePersonalCopy.state(challenge.presentationStatus(at: Date()), outcome: challenge.outcome),
                              warning: challenge.outcome?.kind == .missedGoal,
                              neutral: challenge.outcome?.kind == .inconclusive)
            }
            LiveMetric(value: progress.map { LivePersonalCopy.steps($0, terms: challenge.terms).formatted() } ?? "—", unit: "steps", size: 84)
            if let progress {
                let presentation = PersonalProgressPresentation(progress: progress, terms: challenge.terms)
                LiveProgressRail(progress: presentation.fraction, height: 18)
                Text(presentation.remainingText).font(.subheadline.weight(.medium))
                Text(presentation.stepsText).font(.caption).foregroundStyle(SignalTheme.textSecondary)
            } else {
                LiveProgressRail(progress: nil, height: 18)
                Text("No step data available yet.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            }
            Text(LivePersonalCopy.dates(challenge.terms)).font(.caption).foregroundStyle(SignalTheme.textSecondary)
            Text(challenge.terms.settlementMode == .stripeSandbox
                 ? "\(challenge.terms.commitmentText) test payment"
                 : "\(challenge.terms.commitmentText) test commitment · No money will be charged")
                .font(.caption).foregroundStyle(SignalTheme.textSecondary)
        }
        .padding(20).modifier(LiveCardModifier())
    }

    private func health(_ challenge: PersonalChallengeDetail) -> some View {
        let progress = store.displayedProgress(for: challenge)
        let presentation = PersonalHealthProgressPresentation(progress: progress, terms: challenge.terms,
            status: challenge.presentationStatus(at: Date()), outcome: challenge.outcome,
            uploadDelayed: challenge.id == store.stepProgress.challengeID && store.stepProgress.lastUploadError != nil, now: Date())
        return LivePersonalCard(title: "Apple Health", symbol: "heart") {
            Text(presentation.message)
            if challenge.status.isOpen && !store.healthReadiness.permitsCreation {
                Button(store.isVerifyingHealthAccess ? "Connecting…" : "Connect Apple Health") {
                    Task { _ = await store.verifyHealthAccess(timezone: challenge.terms.timezone) }
                }
                .buttonStyle(LiveSecondaryButtonStyle())
                .disabled(store.isVerifyingHealthAccess || !store.configuration.activitySyncEnabled)
                .accessibilityIdentifier("personal.health.verify")
            }
            Button(working ? "Refreshing…" : "Refresh activity") { Task { await refresh() } }
                .buttonStyle(LiveSecondaryButtonStyle())
                .disabled(working || store.stepProgress.isRefreshing)
                .accessibilityIdentifier("personal.challenge.sync-now")
            if presentation.needsNoDataRecovery {
                Text("Apple Health access may be limited, or this phone may not have recent device-recorded steps.")
                Link("Apple Health help", destination: URL(string: "https://support.apple.com/en-us/HT204351")!)
                    .foregroundStyle(SignalTheme.accent).frame(minHeight: 44)
            }
        }
    }

    private func rules(_ challenge: PersonalChallengeDetail) -> some View {
        let terms = challenge.terms
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                fact("Goal", terms.targetText)
                fact("How it counts", terms.cadence.title)
                fact("Amount", terms.commitmentText)
                fact("Time zone", SignalTimeZone.name(terms.timezone))
                fact("Starts", PersonalTermsDateFormatter.dateTime(terms.startsAt, timezoneIdentifier: terms.timezone))
                fact("Ends", PersonalTermsDateFormatter.dateTime(terms.endsAt, timezoneIdentifier: terms.timezone))
                fact("Updates through", PersonalTermsDateFormatter.dateTime(terms.evidenceCutoff, timezoneIdentifier: terms.timezone))
                Divider()
                Text("Missing or unclear step data never counts as a miss.")
                if terms.settlementMode == .stripeSandbox {
                    Text("Payment test mode — no real money moves.").font(.subheadline.weight(.semibold))
                    Text("By starting, you agree that GameTime may create one \(terms.commitmentText) test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss.")
                    Text("Your test charge is $0 when you meet your goal or step data is missing or unclear. Only a confirmed miss after review can create one \(terms.commitmentText) test charge.")
                } else {
                    Text("Test commitment — no money will be charged.")
                }
            }
            .font(.subheadline).foregroundStyle(SignalTheme.textSecondary).padding(.top, 16)
        } label: {
            Label("Full rules", systemImage: "doc.text").font(.headline)
        }
        .padding(18).modifier(LiveCardModifier(radius: 20, material: true))
        .accessibilityIdentifier("personal.details")
    }

    @ViewBuilder private func days(_ challenge: PersonalChallengeDetail) -> some View {
        if let progress = store.displayedProgress(for: challenge), !progress.days.isEmpty {
            DisclosureGroup("Daily steps") {
                VStack(spacing: 12) {
                    ForEach(progress.days) { day in
                        (dynamicTypeSize.isAccessibilitySize
                                  ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                  : AnyLayout(HStackLayout())) {
                            Text(LivePersonalCopy.day(day.localDate))
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Text(day.state == .future ? "—" : day.totalSteps.formatted())
                                .font(.system(.body, design: .rounded).weight(.bold)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }.padding(.top, 16)
            }
            .font(.headline).padding(18).modifier(LiveCardModifier(radius: 20, material: true))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(SignalTheme.textSecondary)
            Text(value).foregroundStyle(SignalTheme.textPrimary)
        }
    }

    private func canCancel(_ challenge: PersonalChallengeDetail) -> Bool {
        guard store.pendingCancellation == nil, !store.hasPendingCancellationRecoveryIssue else { return false }
        let beforeStart = challenge.status == .scheduled && Date() < challenge.terms.startsAt
        let sandbox = store.configuration.allowsActiveSandboxChallengeCancellation
            && challenge.terms.settlementMode == store.configuration.personalSettlementMode
            && (challenge.status == .scheduled || challenge.status == .active)
        return beforeStart || sandbox
    }

    private var cancellationMessage: String {
        if challenge?.terms.settlementMode == .stripeSandbox {
            return "This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged."
        }
        if store.configuration.allowsActiveSandboxChallengeCancellation {
            return "This ends the test challenge immediately. It will stay in your history, and no money will be charged."
        }
        return "You can only cancel before your challenge starts. Cancelling before it starts closes the test commitment."
    }

    private func refresh() async {
        guard !working else { return }
        working = true
        defer { working = false }
        if let challenge, challenge.permitsActivitySync(at: Date()) {
            if challenge.stepDataPolicy.usesAutomaticHealthProgress {
                if challenge.id == store.stepProgress.challengeID && store.stepProgress.canRefresh {
                    await store.stepProgress.refresh()
                }
            } else {
                await store.sync(challengeID: challengeID)
            }
        }
        await store.openDetail(challengeID: challengeID)
    }
}

private struct LivePersonalPaymentCard: View {
    let challenge: PersonalChallengeDetail
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppModel.self) private var model
    @State private var reason = PersonalReviewReason.userDisputesStepData

    var body: some View {
        let state = store.paymentStatusState(for: challenge.id)
        let presentation = LivePersonalPaymentCopy(challenge: challenge, state: state, now: Date())
        let freshDeadline = store.freshReviewDeadline(for: challenge.id)
        let retained = retainedDeadline(state)
        LivePersonalCard(title: "Payment test status", symbol: "creditcard") {
            Text(presentation.title).font(.headline).foregroundStyle(SignalTheme.textPrimary)
                .accessibilityIdentifier("personal.payment.status.state")
            ForEach(presentation.details, id: \.self) { Text($0) }
            if let confirmed = state.lastConfirmed {
                let date = PersonalTermsDateFormatter.dateTime(confirmed.checkedAt, timezoneIdentifier: challenge.terms.timezone)
                Text(state.refreshFailed ? "Last confirmed \(date). We couldn’t refresh it."
                     : state.isLoading ? "Last confirmed \(date). Refreshing…" : "Checked \(date).")
                    .font(.caption)
            }
            if let deadline = freshDeadline ?? retained {
                Divider()
                Text("Why are you asking for a review?").font(.subheadline.weight(.semibold))
                Picker("Review reason", selection: $reason) {
                    ForEach(PersonalReviewReason.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(freshDeadline != deadline || store.isRequestingReview)
                Button(store.isRequestingReview ? "Requesting review…" : "Request a review") {
                    Task {
                        let succeeded = await store.requestReview(challengeID: challenge.id, reason: reason)
                        PersonalAccessibilityAnnouncements.post(succeeded
                            ? "Review requested. Settlement is paused."
                            : "Review could not be requested. Refresh payment test status and try again.")
                    }
                }
                .buttonStyle(LivePrimaryButtonStyle())
                .disabled(freshDeadline != deadline || store.isRequestingReview
                          || store.freshReviewDeadline(for: challenge.id, at: Date()) != deadline)
                .accessibilityIdentifier("personal.review.request")
            }
            Button(state.isLoading ? "Refreshing…" : "Refresh") {
                Task { await store.refreshPaymentStatus(challengeID: challenge.id) }
            }
            .buttonStyle(LiveSecondaryButtonStyle()).disabled(state.isLoading || store.isRequestingReview)
            .accessibilityIdentifier("personal.payment.status.refresh")
            if let url = model.configuration.supportMailtoURL {
                Link("Contact Support", destination: url).foregroundStyle(SignalTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("personal.payment.status.support")
            }
        }
        .accessibilityIdentifier("personal.payment.status.card")
    }

    private func retainedDeadline(_ state: PersonalPaymentStatusViewState) -> Date? {
        switch state {
        case .loading(let confirmation), .failed(let confirmation):
            guard confirmation?.status.state == .reviewOpen, let deadline = confirmation?.status.reviewDeadline,
                  deadline > Date() else { return nil }
            return deadline
        case .idle, .confirmed: return nil
        }
    }
}

private struct LivePersonalCancellationRecovery: View {
    let challengeID: UUID?
    @Environment(PersonalAccountabilityStore.self) private var store
    @State private var working = false

    private var visible: Bool {
        if store.hasPendingCancellationRecoveryIssue { return true }
        guard let pending = store.pendingCancellation else { return false }
        return challengeID == nil || pending.challengeID == challengeID
    }

    var body: some View {
        if visible {
            LivePersonalCard(title: "Cancellation saved — still trying.", symbol: "arrow.triangle.2.circlepath") {
                Text(store.hasPendingCancellationRecoveryIssue && store.pendingCancellation == nil
                     ? "We couldn’t read the cancellation saved on this phone. Try again to check what happened."
                     : "Your cancellation is saved on this phone. We’ll keep using the same request until it is confirmed.")
                Button(working ? "Retrying cancellation…" : "Retry Cancellation") {
                    working = true
                    Task {
                        let succeeded: Bool
                        if store.pendingCancellation != nil {
                            succeeded = await store.retryPendingCancellation()
                        } else {
                            succeeded = await store.retryPendingCancellationRecovery()
                        }
                        PersonalAccessibilityAnnouncements.post(succeeded ? "Cancellation confirmed." : "Cancellation is still saved. We’ll keep trying.")
                        working = false
                    }
                }
                .buttonStyle(LivePrimaryButtonStyle())
                .disabled(working || store.isMutating || store.isRestoringSavedState)
                .accessibilityIdentifier("personal.cancellation.retry")
            }
            .accessibilityIdentifier("personal.cancellation.pending")
        }
    }
}

private struct LivePersonalPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                (dynamicTypeSize.isAccessibilitySize
                          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                          : AnyLayout(HStackLayout(spacing: 12))) {
                    LiveRoundButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Text(title).liveFont(25, weight: .bold).tracking(-0.8)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                }
                content
            }
            .padding(.horizontal, SignalTheme.contentInset).padding(.top, 13).padding(.bottom, 24)
        }
        .foregroundStyle(SignalTheme.textPrimary).background(SignalTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LivePersonalCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).liveFont(17, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(SignalTheme.textPrimary)
            content.font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiveCardModifier(radius: 20, material: true))
    }
}

private enum LivePersonalCopy {
    static func title(_ terms: FrozenPersonalTerms) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: terms.timezone)
        formatter.dateFormat = "MMMM"
        return "\(formatter.string(from: terms.startsAt)) steps"
    }
    static func dates(_ terms: FrozenPersonalTerms) -> String {
        "\(PersonalTermsDateFormatter.day(terms.startsAt, timezoneIdentifier: terms.timezone))–\(PersonalTermsDateFormatter.day(terms.endsAt.addingTimeInterval(-1), timezoneIdentifier: terms.timezone))"
    }
    static func steps(_ progress: PersonalDisplayedProgress, terms: FrozenPersonalTerms) -> Int {
        if terms.cadence == .cumulative { return progress.totalSteps }
        return (progress.days.first { $0.state == .current } ?? progress.days.last { $0.state != .future })?.totalSteps ?? 0
    }
    static func state(_ status: PersonalChallengePresentationStatus, outcome: PersonalOutcome?) -> String {
        if let outcome {
            switch outcome.kind {
            case .metGoal: return "Your goal met"
            case .missedGoal: return "Missed"
            case .inconclusive: return "Didn’t count"
            }
        }
        switch status {
        case .scheduled: return "Starts soon"
        case .active: return "In progress"
        case .awaitingEvidence: return "Checking activity"
        case .resultPending: return "Result pending"
        case .cancelled: return "Cancelled"
        case .completed: return "Finished"
        }
    }
    static func day(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return "Date unavailable" }
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

/// These are the historical sandbox strings. UI changes do not reinterpret
/// result timing, create a payment retry, or bypass a fresh review deadline.
private struct LivePersonalPaymentCopy {
    let title: String
    let details: [String]
    init(challenge: PersonalChallengeDetail, state: PersonalPaymentStatusViewState, now: Date) {
        guard let status = state.lastConfirmed?.status else {
            title = state.refreshFailed ? "Payment test status could not be confirmed." : "Checking payment test status…"
            details = []
            return
        }
        switch status.state {
        case .methodSaved:
            title = "Test method saved."
            details = ["No test charge exists."]
        case .reviewOpen:
            guard let deadline = status.reviewDeadline else {
                title = "Payment test status could not be confirmed."; details = []; return
            }
            if deadline <= now {
                title = "Review window ended — settlement update pending."
                details = ["Refresh to check the latest payment test status."]
            } else {
                title = "Goal missed — review open. Settlement is paused."
                details = ["Ask us to review this result by \(PersonalTermsDateFormatter.dateTime(deadline, timezoneIdentifier: challenge.terms.timezone)).",
                           "Only a confirmed miss after review can create one \(challenge.terms.commitmentText) test charge."]
            }
        case .underReview:
            title = "Under review — settlement paused."; details = []
        case .waived:
            title = "This one didn’t count — $0 test charge."; details = []
        case .noCharge:
            switch challenge.outcome?.kind {
            case .metGoal: title = "Goal met — $0 test charge."
            case .missedGoal, .inconclusive: title = "This one didn’t count — $0 test charge."
            case nil: title = "Challenge closed — $0 test charge."
            }
            details = []
        case .chargePending:
            title = "Processing one \(challenge.terms.commitmentText) test charge."; details = []
        case .charged:
            title = "Test charge complete — sandbox transaction recorded."; details = []
        case .requiresAction, .collectionFailed:
            title = "Test payment needs your attention. We won’t try again automatically."; details = []
        }
    }
}
