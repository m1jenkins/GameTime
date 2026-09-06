#if DEBUG || STAGING
import SwiftUI

struct PerformanceCommitmentHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var creation: CommitmentCreationSheet?
    private var store: PerformanceCommitmentStore { model.performanceCommitments }

    var body: some View {
        Group {
            if model.configuration.performanceCommitmentRuntimeEnabled {
                List {
                    CommitmentDisclosure()
                    if creation == nil { CommitmentRecoverySection(store: store) }
                    Section {
                        Button("Set a running goal") { creation = CommitmentCreationSheet() }
                            .disabled(!store.canStartRequest)
                            .accessibilityIdentifier("commitment.create")
                        Text("Choose a 5K time to beat and give yourself 28–90 days.")
                    }
                    Section("Your goals") {
                        if store.isLoading { ProgressView("Loading your goals…") }
                        if store.agreements.isEmpty && !store.isLoading {
                            Text("No saved goals to show. Set a goal or refresh to check again.")
                        }
                        ForEach(store.agreements) { agreement in
                            NavigationLink {
                                PerformanceCommitmentDetailView(commitmentID: agreement.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(agreement.terms.targetText).font(.headline)
                                    Text(store.lifecycles[agreement.id]?.progressText ?? "Refresh to check result status")
                                    Text("Finish before \(agreement.deadlineAt.text(zone: agreement.displayTimezone))")
                                        .font(.subheadline)
                                }
                            }
                            .accessibilityIdentifier("commitment.row.\(agreement.id.uuidString.lowercased())")
                        }
                        if store.hasMore {
                            Button("Load earlier goals") { Task { await store.refresh(loadMore: true) } }
                                .disabled(store.isLoading || store.isSending)
                        }
                    }
                }
                .refreshable { await store.refresh() }
            } else {
                ContentUnavailableView("Running goals aren’t available", systemImage: "flag.checkered",
                    description: Text("Return to You to see what’s available."))
            }
        }
        .navigationTitle("Running goals")
        .daybreakScreenChrome()
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                .disabled(store.isLoading || store.isSending)
                .accessibilityIdentifier("commitment.refresh")
        }
        .task(id: store.actorID) { await store.refresh() }
        .onChange(of: store.actorID) { _, _ in creation = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .sheet(item: $creation) { _ in PerformanceCommitmentCreationView() }
    }
}

private struct CommitmentCreationSheet: Identifiable { let id = UUID() }

struct CommitmentDisclosure: View {
    var body: some View {
        Text("Simulated stakes — no real money moves.")
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("commitment.disclosure")
    }
}

struct CommitmentRecoverySection: View {
    let store: PerformanceCommitmentStore
    var body: some View {
        if let request = store.pending {
            Section("Saved request") {
                Text(request.operation.summary)
                if case .create(let draft, _, _) = request.operation {
                    Text("Saved target: 5K in under \(draft.targetSeconds / 60):\(String(format: "%02d", draft.targetSeconds % 60)).")
                    Text("Starts: \(draft.startsAt.text(zone: draft.displayTimezone))")
                    Text("Finish before: \(draft.deadlineAt.text(zone: draft.displayTimezone))")
                    Text("$20 simulated amount · $0 fee")
                }
                Text("We haven’t confirmed this update. Retry the same saved request to check what happened.")
                Button("Retry saved request") { Task { await store.retry() } }
                    .disabled(store.isSending || store.isLoading || store.storageBlocked)
                    .accessibilityIdentifier("commitment.retry")
            }
        }
        if let error = store.errorMessage {
            Section {
                Text(error).accessibilityIdentifier("commitment.error")
                Button("Refresh goals") { Task { await store.refresh() } }
                    .disabled(store.isSending || store.isLoading)
            }
        }
    }
}

struct PerformanceCommitmentCreationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 25
    @State private var seconds = 0
    @State private var durationDays = 56
    @State private var startsAt = Date(timeIntervalSince1970:
        (Date().addingTimeInterval(86400).timeIntervalSince1970 / 60).rounded(.down) * 60)
    @State private var consent = false
    @State private var createdID: UUID?
    private var store: PerformanceCommitmentStore { model.performanceCommitments }
    private var zone: String { model.profile?.timezone ?? TimeZone.current.identifier }
    private var draft: PerformanceCommitmentDraft {
        PerformanceCommitmentDraft(targetSeconds: minutes * 60 + seconds,
            startsAt: PerformanceCommitmentInstant(date: startsAt),
            deadlineAt: PerformanceCommitmentInstant(date: startsAt.addingTimeInterval(Double(durationDays) * 86400)),
            displayTimezone: zone)
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentDisclosure()
                CommitmentRecoverySection(store: store)
                if let createdID {
                    Section("Goal saved") {
                        Text("Your agreement is saved. You can read the rules and check for result updates in your goal.")
                        NavigationLink("Open your goal") {
                            PerformanceCommitmentDetailView(commitmentID: createdID)
                        }
                        .accessibilityIdentifier("commitment.receipt")
                    }
                } else if let preview = store.previewedTerms {
                    CommitmentTermsSections(terms: preview.terms)
                    Section("Your agreement") {
                        Toggle("I agree to these rules and the $20 simulated amount.", isOn: $consent)
                            .disabled(!store.canStartRequest)
                            .accessibilityIdentifier("commitment.consent")
                        Text("A confirmed miss after review loses the $20 simulated amount. Every other outcome returns it in the simulation. No real money is held, charged, owed or paid out.")
                        Button("Save my goal") {
                            Task {
                                await store.submit(.create(draft: draft, termsDigest: preview.termsDigest, consent: consent))
                                recordCreation()
                            }
                        }
                        .disabled(!consent || !store.canStartRequest)
                        .accessibilityIdentifier("commitment.save")
                        Button("Change goal") {
                            consent = false
                            store.invalidatePreview()
                        }
                        .disabled(store.pending != nil || store.isSending)
                    }
                } else {
                    Section {
                        Text("This trial lets you save a goal and read its result history. Adding race attempts and training updates from your phone is still being built.")
                    }
                    Section("Beat this 5K time") {
                        Stepper("Minutes: \(minutes)", value: $minutes, in: 1...1439)
                            .accessibilityIdentifier("commitment.minutes")
                        Stepper("Seconds: \(seconds)", value: $seconds, in: 0...59)
                        Text("Finish in less than \(minutes):\(String(format: "%02d", seconds)). Matching that time does not meet this goal.")
                    }
                    .disabled(store.pending != nil || store.isSending)
                    Section("Give yourself time") {
                        DatePicker("Starts", selection: $startsAt,
                            in: Date().addingTimeInterval(60)...Date().addingTimeInterval(29 * 86400),
                            displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, TimeZone(identifier: zone) ?? .gmt)
                        Stepper("\(durationDays) days", value: $durationDays, in: 28...90)
                        Text("Each day is 24 elapsed hours. A clock change can shift the finish time shown in \(zone).")
                    }
                    .disabled(store.pending != nil || store.isSending)
                    Section {
                        Button(store.isPreviewing ? "Loading rules…" : "Review goal") {
                            consent = false
                            Task { await store.preview(draft) }
                        }
                        .disabled(!store.canStartRequest || store.isPreviewing)
                        .accessibilityIdentifier("commitment.preview")
                    }
                    .disabled(store.pending != nil || store.isSending)
                }
            }
            .navigationTitle(createdID == nil ? (store.previewedTerms == nil ? "Set a goal" : "Review goal") : "Goal saved")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onChange(of: draft) { _, _ in
                consent = false
                store.invalidatePreview()
            }
            .onChange(of: store.lastConfirmedID) { _, _ in recordCreation() }
            .onChange(of: store.actorID) { _, _ in dismiss() }
            .onDisappear { store.invalidatePreview() }
        }
    }

    private func recordCreation() {
        if case .create = store.lastConfirmedOperation { createdID = store.lastConfirmedID }
    }
}

struct CommitmentTermsSections: View {
    let terms: PerformanceCommitmentTerms
    private var zone: String { terms.displayTimezone }
    var body: some View {
        Section("Your goal at a glance") {
            Text(terms.targetText).font(.headline)
            Text("Starts: \(terms.startsAt.text(zone: zone))")
            Text("Finish before: \(terms.deadlineAt.text(zone: zone))")
            Text("Name each event before it starts. Only fictional organizer 5K chip times count in this trial. Beat your target in whole seconds; matching it is not enough. Notes and milestones do not count as race results.")
            Text("$20 simulated amount · $0 fee. A confirmed miss after review loses the simulated amount; every other outcome returns it. No real money is held or moved, and no recipient has been selected.")
                .accessibilityIdentifier("commitment.summary-amount")
            Text("You can cancel before the start, withdraw after it starts, or report an injury. These exits return the simulated amount. Your history stays available.")
            Text("You have seven full days after each saved result notice to ask for review. Missing results or silence alone never mean you missed your goal.")
        }
        Section {
            DisclosureGroup("Full goal rules") {
                VStack(alignment: .leading, spacing: 20) {
                    fullRules
                }
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("commitment.full-rules")
        }
    }

    @ViewBuilder
    private var fullRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your goal").font(.headline).accessibilityAddTraits(.isHeader)
            Text(terms.targetText).font(.headline)
            Text("An official outdoor 5K, timed from crossing the start to crossing the finish. Times count in whole seconds; matching your target is not enough.")
            Text("Starts: \(terms.startsAt.text(zone: zone))")
            Text("Finish before: \(terms.deadlineAt.text(zone: zone))")
            Text("A run may start at the first instant; it must finish before the deadline.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("What counts").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Only fictional organizer results are supported in this trial. Name each event before it starts. A reviewer checks the result independently.")
            Text("Any qualifying attempt that beats your target meets the goal. A later slower run does not undo it. Your notes and milestones do not count as race results.")
            Text("Results due: \(terms.resultsDueAt.text(zone: zone))")
            Text("A missed goal needs your explicit confirmation that all attempts are included, or that you made no attempts, and confirmed results after review. Silence or missing results alone never means you missed.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Review and stopping").font(.headline).accessibilityAddTraits(.isHeader)
            Text("You have seven full days after each saved result notice to ask for review. The reviewer has seven full days after you ask. A correction creates a new notice and deadline.")
            Text("If results or review cannot be confirmed in time, this goal does not count against you.")
            Text("Final result deadline: \(terms.finalityDueAt.text(zone: zone))")
            Text("You can cancel before the start, withdraw after it starts, or report an injury. Ending the goal preserves its history and returns the simulated amount.")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Simulated amount").font(.headline).accessibilityAddTraits(.isHeader)
            Text("$20 simulated amount · $0 fee")
            Text("No real money is held or moved. No recipient has been selected for any future lost amount. Nothing here can be redeemed.")
        }
    }
}

struct PerformanceCommitmentDetailView: View {
    let commitmentID: UUID
    @Environment(AppModel.self) private var model
    @State private var action: CommitmentActionSheet?
    private var store: PerformanceCommitmentStore { model.performanceCommitments }
    private var agreement: PerformanceCommitmentAgreement? { store.agreements.first { $0.id == commitmentID } }
    var body: some View {
        List {
            CommitmentDisclosure()
            if action == nil { CommitmentRecoverySection(store: store) }
            if let agreement {
                CommitmentLifecycleSections(store: store, agreement: agreement,
                    onReview: { action = .review($0.proofRevision) }, onClose: { action = .close($0) })
                Section("Saved agreement") {
                    Text(agreement.terms.targetText).font(.headline)
                    Text("Agreed: \(agreement.createdAt.text(zone: agreement.displayTimezone))")
                    DisclosureGroup("Read your rules") { CommitmentTermsSections(terms: agreement.terms) }
                }
                Section {
                    Text("Adding race attempts and training updates from your phone is coming next. Your saved agreement and result history are available here.")
                }
            } else {
                Text("We couldn’t load this goal. Refresh to try again.")
                    .accessibilityIdentifier("commitment.unavailable")
            }
        }
        .navigationTitle("Your running goal")
        .daybreakScreenChrome()
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refreshDetail(commitmentID) } }
                .disabled(store.isSending || store.isLoading)
                .accessibilityIdentifier("commitment.detail-refresh")
        }
        .refreshable { await store.refreshDetail(commitmentID) }
        .task(id: store.actorID) { await store.refreshDetail(commitmentID) }
        .onChange(of: store.actorID) { _, _ in action = nil }
        .sheet(item: $action) { action in
            CommitmentActionView(commitmentID: commitmentID, action: action)
        }
    }
}

enum CommitmentActionSheet: Identifiable {
    case review(Int), close(PerformanceCommitmentCloseReason)
    var id: String {
        switch self { case .review(let revision): "review-\(revision)"; case .close(let reason): "close-\(reason.rawValue)" }
    }
}

private struct CommitmentActionView: View {
    let commitmentID: UUID
    let action: CommitmentActionSheet
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason: PerformanceCommitmentReviewReason?
    private var store: PerformanceCommitmentStore { model.performanceCommitments }
    var body: some View {
        NavigationStack {
            Form {
                CommitmentDisclosure()
                CommitmentRecoverySection(store: store)
                switch action {
                case .review(let revision):
                    if let notice = store.lifecycles[commitmentID]?.notices.first(where: { $0.proofRevision == revision }),
                       let agreement = store.agreements.first(where: { $0.id == commitmentID }) {
                        Section("Result update") {
                            Text(notice.outcome.title)
                            Text("Notice saved: \(notice.recordedAt.text(zone: agreement.displayTimezone))")
                            Text("Ask before: \(min(notice.disputeClosesAt, agreement.terms.finalityDueAt).text(zone: agreement.displayTimezone))")
                            if agreement.terms.finalityDueAt < notice.disputeClosesAt {
                                Text("Full seven-day window ends: \(notice.disputeClosesAt.text(zone: agreement.displayTimezone))")
                                Text("The final result deadline comes first. If there isn’t time for full review, you don’t lose the simulated amount.")
                            }
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Section("What should we check?") {
                            ForEach(PerformanceCommitmentReviewReason.allCases, id: \.self) { option in
                                Button { reason = option } label: {
                                    HStack {
                                        Text(option.title)
                                        Spacer()
                                        if reason == option { Image(systemName: "checkmark") }
                                    }
                                }
                                .accessibilityIdentifier("commitment.review-reason.\(option.rawValue)")
                                .disabled(!store.canFileReview(commitmentID, revision: revision, at: context.date))
                            }
                        }
                        Button("Send review request") {
                            guard let reason else { return }
                            Task {
                                await store.submit(.fileReview(commitmentID: commitmentID, revision: revision, reason: reason))
                                dismissIfConfirmed()
                            }
                        }
                        .disabled(reason == nil || !store.canFileReview(commitmentID, revision: revision, at: context.date))
                        .accessibilityIdentifier("commitment.send-review")
                        if !store.canFileReview(commitmentID, revision: revision, at: context.date), store.pending == nil, !store.isSending {
                            Text("Review is unavailable for this update. Return to your goal and refresh for the latest status.")
                        }
                    }
                case .close(let closeReason):
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Section(closeReason.title) {
                            Text("This ends your goal and keeps it in your history. You won’t lose the simulated amount. No real money moves.")
                            Button("End this goal", role: .destructive) {
                                Task {
                                    await store.submit(.close(commitmentID: commitmentID, reason: closeReason))
                                    dismissIfConfirmed()
                                }
                            }
                            .disabled(!store.canClose(commitmentID, reason: closeReason, at: context.date))
                            .accessibilityIdentifier("commitment.confirm-close")
                            if !store.canClose(commitmentID, reason: closeReason, at: context.date), store.pending == nil, !store.isSending {
                                Text("This action is unavailable. Return to your goal and refresh for the available ways to stop.")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onChange(of: store.lastConfirmedID) { _, _ in dismissIfConfirmed() }
            .onChange(of: store.actorID) { _, _ in dismiss() }
        }
    }
    private var title: String { switch action { case .review: "Ask for review"; case .close(let reason): reason.title } }
    private func dismissIfConfirmed() {
        guard store.lastConfirmedID == commitmentID else { return }
        switch (action, store.lastConfirmedOperation) {
        case (.review(let revision), .fileReview(_, let saved, _)) where revision == saved: dismiss()
        case (.close(let reason), .close(_, let saved)) where reason == saved: dismiss()
        default: break
        }
    }
}

private extension PerformanceCommitmentMutation {
    var summary: String {
        switch self {
        case .create: "Save your running goal"
        case .fileReview(_, _, let reason): "Ask for review: \(reason.title)"
        case .close(_, let reason): reason.title
        }
    }
}
#endif
