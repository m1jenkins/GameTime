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
        ScrollView {
            LazyVStack(spacing: 11) {
                progressRail(completedSteps: 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Who’s in?")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 27,
                                relativeTo: .title2
                            )
                        )
                        .tracking(-0.8)
                    Text(
                        "Choose up to \(ChallengeTerms.maximumInvitees) accepted friends. Everyone gets the same frozen terms."
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                DaybreakSectionLabel(text: "Friends")
                DaybreakCard {
                    VStack(spacing: 0) {
                        ForEach(model.acceptedFriendships) { card in
                            Toggle(
                                isOn: inviteeSelection(
                                    for: card.otherUserID
                                )
                            ) {
                                HStack(spacing: 11) {
                                    InitialsAvatar(
                                        initials: card.profileCard.initials,
                                        size: 42,
                                        color: CompetitiveTrustTheme
                                            .avatarColor(
                                                for: card.otherUserID
                                            )
                                    )
                                    VStack(
                                        alignment: .leading,
                                        spacing: 2
                                    ) {
                                        Text(card.displayName)
                                            .font(
                                                CompetitiveTrustTheme.uiFont(
                                                    size: 15,
                                                    relativeTo: .headline,
                                                    weight: .bold
                                                )
                                            )
                                        Text("@\(card.handle)")
                                            .font(
                                                CompetitiveTrustTheme.uiFont(
                                                    size: 12.5,
                                                    relativeTo: .caption
                                                )
                                            )
                                            .foregroundStyle(
                                                CompetitiveTrustTheme
                                                    .secondaryText
                                            )
                                    }
                                }
                            }
                            .tint(CompetitiveTrustTheme.coral)
                            .padding(.vertical, 9)
                            .disabled(
                                !draft.inviteeIDs.contains(card.otherUserID)
                                    && draft.inviteeIDs.count
                                        >= ChallengeTerms.maximumInvitees
                            )
                            .accessibilityIdentifier(
                                "challenge.invitee.\(card.otherUserID.uuidString.lowercased())"
                            )

                            if card.id
                                != model.acceptedFriendships.last?.id
                            {
                                Divider()
                                    .overlay(CompetitiveTrustTheme.border)
                            }
                        }
                    }
                }

                Text(
                    "\(draft.inviteeIDs.count) selected · Every invitation is submitted together or none are."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .padding(.horizontal, 6)

                DaybreakSectionLabel(text: "Challenge")
                DaybreakCard {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Title")
                            TextField("Challenge title", text: $draft.title)
                                .font(
                                    CompetitiveTrustTheme.uiFont(
                                        size: 15,
                                        relativeTo: .body,
                                        weight: .semibold
                                    )
                                )
                                .textInputAutocapitalization(.sentences)
                                .submitLabel(.done)
                                .accessibilityIdentifier("challenge.title")
                        }
                        .padding(.vertical, 10)

                        Divider().overlay(CompetitiveTrustTheme.border)

                        Picker("Metric", selection: $draft.metric) {
                            ForEach(ContestMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 8)
                        .onChange(of: draft.metric) {
                            oldMetric,
                            newMetric in
                            if draft.targetValue
                                == oldMetric.suggestedTarget
                            {
                                draft.targetValue =
                                    newMetric.suggestedTarget
                            }
                        }

                        Divider().overlay(CompetitiveTrustTheme.border)

                        Picker("Cadence", selection: $draft.cadence) {
                            ForEach(ContestCadence.allCases) { cadence in
                                Text(cadence.title).tag(cadence)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 8)

                        Divider().overlay(CompetitiveTrustTheme.border)

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
                                .foregroundStyle(
                                    CompetitiveTrustTheme.secondaryText
                                )
                        }
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 15,
                                relativeTo: .body,
                                weight: .semibold
                            )
                        )
                        .padding(.vertical, 10)
                    }
                }

                DaybreakSectionLabel(text: "Window")
                DaybreakCard {
                    VStack(spacing: 0) {
                        DatePicker(
                            "Starts",
                            selection: $draft.startsAt,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding(.vertical, 9)

                        Divider().overlay(CompetitiveTrustTheme.border)

                        DatePicker(
                            "Ends",
                            selection: $draft.endsAt,
                            in: draft.startsAt...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding(.vertical, 9)
                    }
                }

                DaybreakSectionLabel(text: "Commitment")
                DaybreakCard {
                    VStack(spacing: 0) {
                        Stepper(
                            value: $draft.stakeAmountCents,
                            in: 100...100_000,
                            step: 100
                        ) {
                            LabeledContent("Test pledge") {
                                Text(
                                    (Double(draft.stakeAmountCents) / 100)
                                        .formatted(
                                            .currency(code: "USD")
                                        )
                                )
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    CompetitiveTrustTheme.sunInk
                                )
                            }
                        }
                        .padding(.vertical, 9)

                        Divider().overlay(CompetitiveTrustTheme.border)

                        Picker("Charity", selection: $draft.charityID) {
                            Text("Choose a charity").tag(UUID?.none)
                            ForEach(model.charities) { charity in
                                Text(charity.name).tag(Optional(charity.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 8)

                        Divider().overlay(CompetitiveTrustTheme.border)

                        Picker("Tie-break", selection: $draft.tieBreak) {
                            ForEach(ContestTieBreak.allCases) { tieBreak in
                                Text(tieBreak.title).tag(tieBreak)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 8)
                    }
                }

                Text(
                    "This is not a real pledge. Terms become immutable when submitted."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .padding(.horizontal, 6)

                Button("Review immutable terms") {
                    do {
                        reviewedTerms = try draft.validated()
                    } catch {
                        model.presentedError = error.localizedDescription
                    }
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .accessibilityIdentifier("challenge.review")
                .padding(.top, 4)

                Text(
                    "One atomic request creates the challenge and every invitation."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .daybreakScreenChrome()
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
        ScrollView {
            LazyVStack(spacing: 11) {
                progressRail(completedSteps: 3)

                VStack(alignment: .leading, spacing: 9) {
                    TrustStatusPill(
                        text: "Ready to commit",
                        kind: .action
                    )
                    Text("These terms freeze on send.")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 27,
                                relativeTo: .title2
                            )
                        )
                        .tracking(-0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                DaybreakSectionLabel(text: "Immutable terms")
                DaybreakCard {
                    VStack(spacing: 0) {
                        Text(terms.title)
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 20,
                                    relativeTo: .title3
                                )
                            )
                            .tracking(-0.55)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)

                        Divider().overlay(CompetitiveTrustTheme.border)

                        ForEach(terms.inviteeIDs, id: \.self) {
                            inviteeID in
                            reviewTerm(
                                label: terms.inviteeIDs.count == 1
                                    ? "Friend"
                                    : "Invited friend",
                                value: friendName(for: inviteeID)
                            )
                            Divider().overlay(CompetitiveTrustTheme.border)
                        }

                        reviewTerm(
                            label: "Metric",
                            value: terms.metric.title
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Cadence",
                            value: terms.cadence.title
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Target",
                            value: "\(terms.targetValue.formatted()) \(terms.metric.unit)"
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Starts",
                            value: terms.startsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Ends",
                            value: terms.endsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Timezone",
                            value: terms.timezone
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Tie-break",
                            value: terms.tieBreak.title
                        )
                        Divider().overlay(CompetitiveTrustTheme.border)
                        reviewTerm(
                            label: "Roster",
                            value: "\(terms.maxParticipants) people"
                        )
                    }
                }

                DaybreakCard(tone: .pledge) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pledge")
                                .font(
                                    CompetitiveTrustTheme.uiFont(
                                        size: 10,
                                        relativeTo: .caption2,
                                        weight: .bold
                                    )
                                )
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(
                                    CompetitiveTrustTheme.sunInk
                                )
                            Text(
                                "\((Double(terms.stakeAmountCents) / 100).formatted(.currency(code: "USD"))) each"
                            )
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 22,
                                    relativeTo: .title3
                                )
                            )
                        }
                        Spacer(minLength: 8)
                        Text(
                            "To \(charityName(for: terms.charityID)) under the frozen result rules."
                        )
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 12,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                        .multilineTextAlignment(.trailing)
                    }
                }

                DaybreakCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Request ID")
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 11,
                                    relativeTo: .caption,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                        Text(terms.requestID.uuidString.lowercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("challenge.request-id")
                }

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

                Text(reviewFooter(for: terms))
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("Review challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(model.isMutating)
            }
        }
    }

    private func progressRail(completedSteps: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(
                        step <= completedSteps
                            ? CompetitiveTrustTheme.coral
                            : CompetitiveTrustTheme.rail
                    )
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 10.5,
                    relativeTo: .caption2,
                    weight: .bold
                )
            )
            .tracking(0.75)
            .textCase(.uppercase)
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
    }

    private func reviewTerm(
        label: String,
        value: String
    ) -> some View {
        TermRow(label: label, value: value)
            .padding(.vertical, 10)
    }

    private func reviewFooter(for terms: ChallengeTerms) -> String {
        if model.pendingChallenge?.terms.requestID == terms.requestID {
            return "This protected retry survives relaunch. Submit explicitly reuses the saved request UUID and immutable terms; GameTime never retries it automatically."
        }
        return "Before sending, GameTime saves these immutable terms and request UUID in protected app storage."
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
            Group {
                if let contest {
                    ScrollView {
                        LazyVStack(spacing: 11) {
                            VStack(alignment: .leading, spacing: 9) {
                                TrustStatusPill(
                                    text: "Action needed",
                                    kind: .action
                                )
                                Text("Review the frozen terms.")
                                    .font(
                                        CompetitiveTrustTheme.displayFont(
                                            size: 27,
                                            relativeTo: .title2
                                        )
                                    )
                                    .tracking(-0.8)
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(.horizontal, 4)

                            DaybreakSectionLabel(text: "Immutable terms")
                            immutableTermsCard(contest)

                            DaybreakSectionLabel(
                                text: "Your nomination"
                            )
                            DaybreakCard {
                                VStack(spacing: 0) {
                                    Picker(
                                        "Your charity",
                                        selection: $charityID
                                    ) {
                                        Text("Choose a charity")
                                            .tag(UUID?.none)
                                        ForEach(model.charities) { charity in
                                            Text(charity.name)
                                                .tag(Optional(charity.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .padding(.vertical, 8)

                                    Divider()
                                        .overlay(
                                            CompetitiveTrustTheme.border
                                        )

                                    TermRow(
                                        label: "Frozen timezone",
                                        value: model.profile?.timezone ?? "UTC"
                                    )
                                    .padding(.vertical, 10)
                                }
                            }

                            Text(
                                "Acceptance freezes this timezone and charity for the challenge."
                            )
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 11.5,
                                    relativeTo: .caption
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                            .padding(.horizontal, 6)

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
                                        .accessibilityLabel(
                                            "Accepting invitation"
                                        )
                                } else {
                                    Text("Accept fixed terms")
                                }
                            }
                            .buttonStyle(TrustPrimaryButtonStyle())
                            .disabled(charityID == nil || model.isMutating)
                            .accessibilityIdentifier("invitation.accept")
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                    }
                } else {
                    DaybreakCard {
                        EmptyTrustState(
                            title: "Invitation unavailable",
                            message: "Dismiss and refresh the current state.",
                            systemImage: "envelope.badge"
                        )
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .daybreakScreenChrome()
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

    private func immutableTermsCard(_ contest: ContestCard) -> some View {
        DaybreakCard {
            VStack(spacing: 0) {
                Text(contest.title)
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 20,
                            relativeTo: .title3
                        )
                    )
                    .tracking(-0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)

                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm("Metric", contest.metric.title)
                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm("Cadence", contest.cadence.title)
                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm("Target", contest.targetText)
                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm(
                    "Starts",
                    contest.startsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm(
                    "Ends",
                    contest.endsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm("Test pledge", contest.stakeText)
                Divider().overlay(CompetitiveTrustTheme.border)
                invitationTerm("Tie-break", contest.tieBreak.title)

                if let maxParticipants = contest.maxParticipants {
                    Divider().overlay(CompetitiveTrustTheme.border)
                    invitationTerm(
                        "Closed roster",
                        "\(maxParticipants) people"
                    )
                }

                ForEach(contest.resolvedParticipants) { participant in
                    Divider().overlay(CompetitiveTrustTheme.border)
                    invitationTerm(
                        participant.userID == contest.createdBy
                            ? "Creator"
                            : "Roster member",
                        participantName(participant.userID)
                    )
                }

                if
                    let creatorID = contest.createdBy,
                    let creatorCharityID = contest.resolvedParticipants.first(
                        where: { $0.userID == creatorID }
                    )?.charityID
                {
                    Divider().overlay(CompetitiveTrustTheme.border)
                    invitationTerm(
                        "Creator nomination",
                        charityName(creatorCharityID)
                    )
                }
            }
        }
    }

    private func invitationTerm(
        _ label: String,
        _ value: String
    ) -> some View {
        TermRow(
            label: label,
            value: value,
            emphasis: label == "Test pledge"
                ? CompetitiveTrustTheme.sunInk
                : CompetitiveTrustTheme.primaryText
        )
        .padding(.vertical, 10)
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
