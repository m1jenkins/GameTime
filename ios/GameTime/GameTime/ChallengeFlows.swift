import SwiftUI

// MARK: - Challenge creation

struct CreateChallengeFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var draft = ChallengeDraft()
    @State private var reviewedTerms: ChallengeTerms?
    @State private var showingDiscardConfirmation = false

    private var activeReviewedTerms: ChallengeTerms? {
        model.pendingChallenge?.terms ?? reviewedTerms
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
                    if await model.discardPendingChallenge() {
                        reviewedTerms = nil
                        resetDraft()
                    }
                }
            }
            Button("Keep saved request", role: .cancel) {}
        } message: {
            Text(
                "This deletes only the on-device retry record; it does not cancel a contest or invitation the server may already have created. Starting over after a committed request can create a second challenge."
            )
        }
    }

    private var editor: some View {
        Form {
            Section {
                ForEach(model.acceptedFriendships) { card in
                    Toggle(
                        isOn: inviteeSelection(for: card.otherUserID)
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.displayName)
                            Text("@\(card.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(
                        !draft.inviteeIDs.contains(card.otherUserID)
                            && draft.inviteeIDs.count
                                >= ChallengeTerms.maximumInvitees
                    )
                    .accessibilityIdentifier(
                        "challenge.invitee.\(card.otherUserID.uuidString.lowercased())"
                    )
                }
            } header: {
                Text("Friends")
            } footer: {
                Text(
                    "\(draft.inviteeIDs.count) selected · Choose up to \(ChallengeTerms.maximumInvitees). Every invitation is submitted together or none are."
                )
            }

            Section("Challenge") {
                TextField("Challenge title", text: $draft.title)
                    .accessibilityIdentifier("challenge.title")

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
                .accessibilityIdentifier("challenge.review")
            }
            .listRowBackground(Color.clear)
        }
        .trustScreenBackground()
        .navigationTitle("Create challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if draft.charityID == nil {
                draft.charityID = model.charities.first?.id
            }
        }
    }

    private func review(terms: ChallengeTerms) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TrustStatusPill(text: "Ready to commit", kind: .action)
                    Text(terms.title)
                        .font(.title2.bold())
                    Text(
                        "Check every term. Submission creates one contest and \(terms.inviteeIDs.count) \(terms.inviteeIDs.count == 1 ? "invitation" : "invitations") in a single atomic request."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            Section("Immutable terms") {
                ForEach(terms.inviteeIDs, id: \.self) { inviteeID in
                    TermRow(
                        label: terms.inviteeIDs.count == 1
                            ? "Friend"
                            : "Invited friend",
                        value: friendName(for: inviteeID)
                    )
                }
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
                TermRow(label: "Timezone", value: terms.timezone)
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
                TermRow(
                    label: "Roster",
                    value: "\(terms.maxParticipants) people"
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request ID")
                        .foregroundStyle(.secondary)
                    Text(terms.requestID.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("challenge.request-id")
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            Section {
                Button {
                    Task {
                        if let id = await model.createChallenge(terms) {
                            router.selectedTab = .challenges
                            router.challengesPath = [.contest(id)]
                            dismiss()
                        }
                    }
                } label: {
                    if model.isMutating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Submitting challenge")
                    } else {
                        Text(
                            terms.inviteeIDs.count == 1
                                ? "Submit challenge and invitation"
                                : "Submit challenge and \(terms.inviteeIDs.count) invitations"
                        )
                    }
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(model.isMutating)
                .accessibilityIdentifier("challenge.submit")

                if model.pendingChallenge?.terms.requestID == terms.requestID {
                    Button(
                        "Discard local retry record",
                        role: .destructive
                    ) {
                        showingDiscardConfirmation = true
                    }
                    .disabled(model.isMutating)
                    .accessibilityIdentifier(
                        "challenge.pending.discard-review"
                    )
                } else {
                    Button("Back to edit") {
                        reviewedTerms = nil
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(model.isMutating)
                }
            } footer: {
                if model.pendingChallenge?.terms.requestID == terms.requestID {
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
        .navigationTitle("Review challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(model.isMutating)
            }
        }
    }

    private func inviteeSelection(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                draft.inviteeIDs.contains(id)
            },
            set: { isSelected in
                if isSelected {
                    guard
                        draft.inviteeIDs.count
                            < ChallengeTerms.maximumInvitees
                    else {
                        return
                    }
                    draft.inviteeIDs.insert(id)
                } else {
                    draft.inviteeIDs.remove(id)
                }
            }
        )
    }

    private func friendName(for id: UUID) -> String {
        model.acceptedFriendships.first { $0.otherUserID == id }?
            .displayName ?? "Account \(id.uuidString.lowercased())"
    }

    private func charityName(for id: UUID) -> String {
        model.charities.first { $0.id == id }?.name
            ?? "Charity \(id.uuidString.lowercased())"
    }

    private func resetDraft() {
        draft = ChallengeDraft()
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
                            label: "Starts",
                            value: contest.startsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        TermRow(
                            label: "Ends",
                            value: contest.endsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        TermRow(
                            label: "Test pledge",
                            value: contest.stakeText,
                            emphasis: CompetitiveTrustTheme.amber
                        )
                        TermRow(
                            label: "Tie-break",
                            value: contest.tieBreak.title
                        )
                        if let maxParticipants = contest.maxParticipants {
                            TermRow(
                                label: "Closed roster",
                                value: "\(maxParticipants) people"
                            )
                        }
                        ForEach(
                            contest.resolvedParticipants
                        ) { participant in
                            TermRow(
                                label: participant.userID
                                    == contest.createdBy
                                    ? "Creator"
                                    : "Roster member",
                                value: participantName(
                                    participant.userID
                                )
                            )
                        }
                        if
                            let creatorID = contest.createdBy,
                            let creatorCharityID =
                                contest.resolvedParticipants.first(
                                    where: {
                                        $0.userID == creatorID
                                    }
                                )?.charityID
                        {
                            TermRow(
                                label: "Creator nomination",
                                value: charityName(creatorCharityID)
                            )
                        }
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

    private func participantName(_ userID: UUID) -> String {
        if userID == model.userID {
            return "You"
        }
        if let card = model.friendshipCards.first(where: {
            $0.otherUserID == userID
        }) {
            return card.displayName
        }
        return "Account \(userID.uuidString.lowercased())"
    }

    private func charityName(_ charityID: UUID) -> String {
        model.charities.first(where: { $0.id == charityID })?.name
            ?? "Charity \(charityID.uuidString.lowercased())"
    }
}
