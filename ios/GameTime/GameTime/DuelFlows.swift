import SwiftUI

struct CreateDuelFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var draft = DuelDraft()
    @State private var reviewedTerms: DuelTerms?
    @State private var showingDiscardConfirmation = false

    private var activeReviewedTerms: DuelTerms? {
        model.pendingDuel?.terms ?? reviewedTerms
    }

    var body: some View {
        NavigationStack {
            if let activeReviewedTerms {
                review(terms: activeReviewedTerms)
            } else {
                editor
            }
        }
        .interactiveDismissDisabled(model.isMutating)
        .confirmationDialog(
            "Discard the local retry record?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard local retry", role: .destructive) {
                Task {
                    if await model.discardPendingDuel() {
                        reviewedTerms = nil
                        resetDraft()
                    }
                }
            }
            Button("Keep saved request", role: .cancel) {}
        } message: {
            Text(
                "This deletes only the on-device retry record; it does not cancel a contest or invitation the server may already have created. Starting over after a committed request can create a second duel."
            )
        }
    }

    private var editor: some View {
        Form {
            Section("Opponent") {
                Picker("Friend", selection: $draft.inviteeID) {
                    Text("Choose a friend").tag(UUID?.none)
                    ForEach(model.acceptedFriendships) { card in
                        Text("\(card.displayName) · @\(card.handle)")
                            .tag(Optional(card.otherUserID))
                    }
                }
                .accessibilityIdentifier("duel.opponent")
            }

            Section("Challenge") {
                TextField("Duel title", text: $draft.title)
                    .accessibilityIdentifier("duel.title")

                Picker("Metric", selection: $draft.metric) {
                    ForEach(ContestMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .onChange(of: draft.metric) { oldMetric, newMetric in
                    if draft.targetValue == oldMetric.suggestedTarget {
                        draft.targetValue = newMetric.suggestedTarget
                    }
                }

                Picker("Cadence", selection: $draft.cadence) {
                    ForEach(ContestCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }

                HStack {
                    Text("Target")
                    Spacer()
                    TextField(
                        "Target",
                        value: $draft.targetValue,
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    Text(draft.metric.unit)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Window") {
                DatePicker(
                    "Starts",
                    selection: $draft.startsAt,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                DatePicker(
                    "Ends",
                    selection: $draft.endsAt,
                    in: draft.startsAt...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Section {
                Stepper(
                    value: $draft.stakeAmountCents,
                    in: 100...100_000,
                    step: 100
                ) {
                    LabeledContent("Test pledge") {
                        Text(
                            (Double(draft.stakeAmountCents) / 100)
                                .formatted(.currency(code: "USD"))
                        )
                        .foregroundStyle(CompetitiveTrustTheme.amber)
                    }
                }

                Picker("Charity", selection: $draft.charityID) {
                    Text("Choose a charity").tag(UUID?.none)
                    ForEach(model.charities) { charity in
                        Text(charity.name).tag(Optional(charity.id))
                    }
                }

                Picker("Tie-break", selection: $draft.tieBreak) {
                    ForEach(ContestTieBreak.allCases) { tieBreak in
                        Text(tieBreak.title).tag(tieBreak)
                    }
                }
            } header: {
                Text("Commitment")
            } footer: {
                Text(
                    "This staging treatment is not a real pledge. Terms become immutable when submitted."
                )
            }

            Section {
                Button("Review immutable terms") {
                    do {
                        reviewedTerms = try draft.validated()
                    } catch {
                        model.presentedError = error.localizedDescription
                    }
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .accessibilityIdentifier("duel.review")
            }
            .listRowBackground(Color.clear)
        }
        .trustScreenBackground()
        .navigationTitle("Create duel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if draft.inviteeID == nil {
                draft.inviteeID = model.acceptedFriendships.first?.otherUserID
            }
            if draft.charityID == nil {
                draft.charityID = model.charities.first?.id
            }
        }
    }

    private func review(terms: DuelTerms) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TrustStatusPill(text: "Ready to commit", kind: .action)
                    Text(terms.title)
                        .font(.title2.bold())
                    Text(
                        "Check every term. Submission creates the contest and invitation in one atomic request."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            Section("Immutable terms") {
                TermRow(
                    label: "Opponent",
                    value: opponentName(for: terms.inviteeID)
                )
                TermRow(label: "Metric", value: terms.metric.title)
                TermRow(label: "Cadence", value: terms.cadence.title)
                TermRow(
                    label: "Target",
                    value:
                        "\(terms.targetValue.formatted()) \(terms.metric.unit)"
                )
                TermRow(
                    label: "Starts",
                    value: terms.startsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                TermRow(
                    label: "Ends",
                    value: terms.endsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                TermRow(
                    label: "Test pledge",
                    value: (Double(terms.stakeAmountCents) / 100)
                        .formatted(.currency(code: "USD")),
                    emphasis: CompetitiveTrustTheme.amber
                )
                TermRow(
                    label: "Charity",
                    value: charityName(for: terms.charityID)
                )
                TermRow(label: "Tie-break", value: terms.tieBreak.title)
                TermRow(label: "Roster", value: "2 people")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request ID")
                        .foregroundStyle(.secondary)
                    Text(terms.requestID.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("duel.request-id")
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            Section {
                Button {
                    Task {
                        if let id = await model.createDuel(terms) {
                            router.selectedTab = .challenges
                            router.challengesPath = [.contest(id)]
                            dismiss()
                        }
                    }
                } label: {
                    if model.isMutating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Submitting duel")
                    } else {
                        Text("Submit duel and invitation")
                    }
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(model.isMutating)
                .accessibilityIdentifier("duel.submit")

                if model.pendingDuel?.terms.requestID == terms.requestID {
                    Button(
                        "Discard local retry record",
                        role: .destructive
                    ) {
                        showingDiscardConfirmation = true
                    }
                    .disabled(model.isMutating)
                    .accessibilityIdentifier(
                        "duel.pending.discard-review"
                    )
                } else {
                    Button("Back to edit") {
                        reviewedTerms = nil
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(model.isMutating)
                }
            } footer: {
                if model.pendingDuel?.terms.requestID == terms.requestID {
                    Text(
                        "This protected retry survives relaunch. Submit explicitly reuses the saved request UUID and immutable terms; GameTime never retries it automatically."
                    )
                } else {
                    Text(
                        "Before the request is sent, GameTime saves these immutable terms and request UUID in protected app storage."
                    )
                }
            }
            .listRowBackground(Color.clear)
        }
        .trustScreenBackground()
        .navigationTitle("Review duel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(model.isMutating)
            }
        }
    }

    private func opponentName(for id: UUID) -> String {
        model.acceptedFriendships.first { $0.otherUserID == id }?
            .displayName ?? "Account \(id.uuidString.lowercased())"
    }

    private func charityName(for id: UUID) -> String {
        model.charities.first { $0.id == id }?.name
            ?? "Charity \(id.uuidString.lowercased())"
    }

    private func resetDraft() {
        draft = DuelDraft()
        draft.inviteeID = model.acceptedFriendships.first?.otherUserID
        draft.charityID = model.charities.first?.id
    }
}

struct AcceptInvitationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let contestID: UUID
    @State private var charityID: UUID?

    private var contest: ContestCard? {
        model.contests.first { $0.id == contestID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let contest {
                    Section("Immutable terms") {
                        TermRow(label: "Challenge", value: contest.title)
                        TermRow(label: "Metric", value: contest.metric.title)
                        TermRow(label: "Cadence", value: contest.cadence.title)
                        TermRow(label: "Target", value: contest.targetText)
                        TermRow(
                            label: "Test pledge",
                            value: contest.stakeText,
                            emphasis: CompetitiveTrustTheme.amber
                        )
                        TermRow(
                            label: "Tie-break",
                            value: contest.tieBreak.title
                        )
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)

                    Section {
                        Picker("Your charity", selection: $charityID) {
                            Text("Choose a charity").tag(UUID?.none)
                            ForEach(model.charities) { charity in
                                Text(charity.name).tag(Optional(charity.id))
                            }
                        }
                        LabeledContent("Frozen timezone") {
                            Text(model.profile?.timezone ?? "UTC")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Your nomination")
                    } footer: {
                        Text(
                            "Acceptance freezes this timezone and charity for the contest."
                        )
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)

                    Section {
                        Button {
                            guard let charityID else { return }
                            Task {
                                await model.acceptInvitation(
                                    contestID: contest.id,
                                    charityID: charityID
                                )
                                if model.contests.first(
                                    where: { $0.id == contest.id }
                                )?.myStatus == .accepted {
                                    dismiss()
                                }
                            }
                        } label: {
                            if model.isMutating {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel("Accepting invitation")
                            } else {
                                Text("Accept fixed terms")
                            }
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                        .disabled(charityID == nil || model.isMutating)
                        .accessibilityIdentifier("invitation.accept")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        "Invitation unavailable",
                        systemImage: "envelope.badge",
                        description: Text(
                            "Dismiss and refresh the current state."
                        )
                    )
                }
            }
            .trustScreenBackground()
            .navigationTitle("Review invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isMutating)
                }
            }
            .onAppear {
                charityID = charityID ?? model.charities.first?.id
            }
        }
        .interactiveDismissDisabled(model.isMutating)
    }
}
