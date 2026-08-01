import SwiftUI

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.demoMode) private var demoMode
    @State private var handle = ""
    @FocusState private var handleFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 11) {
                subtitle
                loadStateCard
                findPersonCard
                exactMatchState
                incomingSection
                acceptedSection
                outgoingSection
                emptyState
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .daybreakScreenChrome()
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refresh()
        }
    }

    private var subtitle: some View {
        Text(summaryText)
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 12.5,
                    relativeTo: .caption,
                    weight: .semibold
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
    }

    private var summaryText: String {
        let friendCount = model.acceptedFriendships.count
        var parts = [
            "\(friendCount) \(friendCount == 1 ? "friend" : "friends")"
        ]
        if !model.incomingFriendships.isEmpty {
            parts.append("\(model.incomingFriendships.count) incoming")
        }
        if !model.outgoingFriendships.isEmpty {
            parts.append("\(model.outgoingFriendships.count) sent")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var loadStateCard: some View {
        switch model.loadState {
        case .loading, .failed:
            DaybreakCard {
                InlineLoadStateView(
                    state: model.loadState,
                    retry: { Task { await model.refresh() } }
                )
            }
        case .idle, .loaded, .empty:
            EmptyView()
        }
    }

    private var findPersonCard: some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Find one person")
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11,
                            relativeTo: .caption,
                            weight: .bold
                        )
                    )
                    .tracking(1.05)
                    .textCase(.uppercase)
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) {
                        handleField
                        findButton
                    }
                    VStack(spacing: 9) {
                        handleField
                        findButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                Text(findFooterText)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .lineSpacing(2)
            }
        }
    }

    private var handleField: some View {
        HStack(spacing: 7) {
            Image(systemName: "at")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                .accessibilityHidden(true)
            TextField("Exact handle", text: $handle)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 14.5,
                        relativeTo: .body
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($handleFocused)
                .submitLabel(.search)
                .onSubmit(submit)
                .accessibilityIdentifier("friends.exact-handle")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 42)
        .background(CompetitiveTrustTheme.paper, in: Capsule())
        .overlay {
            Capsule()
                .stroke(CompetitiveTrustTheme.border, lineWidth: 1)
        }
    }

    private var findButton: some View {
        Button("Find", action: submit)
            .buttonStyle(
                TrustCompactButtonStyle(tone: .primary)
            )
            .disabled(
                model.isMutating
                    || ExactHandleSubmission.normalized(handle) == nil
            )
            .accessibilityIdentifier("friends.find")
    }

    private var findFooterText: String {
        if demoMode.isActive {
            return "Try @david1 or @david2. Demo requests are accepted immediately."
        }
        return "Exact handles only. GameTime does not offer fuzzy or enumerable people search."
    }

    @ViewBuilder
    private var exactMatchState: some View {
        if let result = model.exactHandleResult {
            DaybreakSectionLabel(text: "Exact match")
            DaybreakCard {
                HStack(spacing: 12) {
                    InitialsAvatar(
                        initials: result.initials,
                        color: CompetitiveTrustTheme.avatarColor(
                            for: result.id
                        )
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.displayName)
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 15,
                                    relativeTo: .headline,
                                    weight: .bold
                                )
                            )
                        Text("@\(result.handle)")
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 13,
                                    relativeTo: .subheadline
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                    }
                    Spacer(minLength: 8)
                    exactMatchAction(result)
                }
            }
        } else if let submitted = model.lastSubmittedHandle,
            ExactHandleSubmission.normalized(submitted) != nil,
            !model.isMutating
        {
            DaybreakSectionLabel(text: "Exact match")
            DaybreakCard {
                Label(
                    "No profile matched @\(submitted) exactly.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13.5,
                        relativeTo: .subheadline
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var incomingSection: some View {
        if !model.incomingFriendships.isEmpty {
            DaybreakSectionLabel(text: "Incoming")
            DaybreakCard {
                VStack(spacing: 0) {
                    ForEach(model.incomingFriendships) { card in
                        FriendshipCardRow(
                            card: card,
                            actionTitle: "Accept",
                            action: {
                                Task {
                                    await model.acceptFriendship(
                                        with: card.otherUserID
                                    )
                                }
                            }
                        )
                        .padding(.vertical, 9)

                        if card.id != model.incomingFriendships.last?.id {
                            Divider()
                                .overlay(CompetitiveTrustTheme.border)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var acceptedSection: some View {
        if !model.acceptedFriendships.isEmpty {
            DaybreakSectionLabel(text: "Friends")
            DaybreakCard {
                VStack(spacing: 0) {
                    ForEach(model.acceptedFriendships) { card in
                        acceptedFriendRow(card)
                            .padding(.vertical, 9)

                        if card.id != model.acceptedFriendships.last?.id {
                            Divider()
                                .overlay(CompetitiveTrustTheme.border)
                        }
                    }
                }
            }
        }
    }

    private func acceptedFriendRow(_ card: FriendshipCard) -> some View {
        Button {
            router.friendsPath.append(.profile(card.otherUserID))
        } label: {
            HStack(spacing: 12) {
                InitialsAvatar(
                    initials: card.profileCard.initials,
                    color: CompetitiveTrustTheme.avatarColor(
                        for: card.otherUserID
                    )
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.displayName)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 15,
                                relativeTo: .headline,
                                weight: .bold
                            )
                        )
                    Text(friendSubtitle(card))
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 12.5,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.guide)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(card.displayName), @\(card.handle), \(friendSubtitle(card))"
        )
    }

    @ViewBuilder
    private var outgoingSection: some View {
        if !model.outgoingFriendships.isEmpty {
            DaybreakSectionLabel(text: "Sent")
            DaybreakCard {
                VStack(spacing: 0) {
                    ForEach(model.outgoingFriendships) { card in
                        FriendshipCardRow(
                            card: card,
                            actionTitle: "Cancel",
                            action: {
                                Task {
                                    await model.removeFriendship(
                                        with: card.otherUserID
                                    )
                                }
                            }
                        )
                        .padding(.vertical, 9)

                        if card.id != model.outgoingFriendships.last?.id {
                            Divider()
                                .overlay(CompetitiveTrustTheme.border)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.friendshipCards.isEmpty, model.loadState != .loading {
            DaybreakCard {
                EmptyTrustState(
                    title: "No relationships yet",
                    message:
                        "Submit the exact handle someone shared with you to send a request. You can’t be found by phone, email, or broad search.",
                    systemImage: "person.2"
                )
            }

            if let profile = model.profile {
                DaybreakCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your handle")
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 12,
                                    relativeTo: .caption,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                        Text("@\(profile.handle)")
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 24,
                                    relativeTo: .title2
                                )
                            )
                            .tracking(-0.65)
                        Text(
                            "Share it however you like — an exact handle is the only way in."
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
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func exactMatchAction(_ result: ProfileCard) -> some View {
        if result.id == model.userID {
            TrustStatusPill(text: "You", kind: .neutral)
        } else if let existing = model.friendshipCards.first(
            where: { $0.otherUserID == result.id }
        ) {
            let text = existing.status == .accepted ? "Friends" : "Pending"
            TrustStatusPill(
                text: text,
                kind: existing.status == .accepted ? .verified : .action
            )
        } else {
            Button("Add") {
                Task {
                    await model.requestFriendship(with: result.id)
                }
            }
            .buttonStyle(
                TrustCompactButtonStyle(tone: .primary)
            )
            .accessibilityLabel("Add \(result.displayName)")
        }
    }

    private func friendSubtitle(_ card: FriendshipCard) -> String {
        let count = sharedChallengeCount(with: card.otherUserID)
        if count == 0 {
            return "@\(card.handle)"
        }
        return "@\(card.handle) · \(count) \(count == 1 ? "challenge" : "challenges") together"
    }

    private func sharedChallengeCount(with userID: UUID) -> Int {
        model.contests.filter { contest in
            contest.myStatus == .accepted
                && contest.resolvedParticipants.contains {
                    $0.userID == userID && $0.status == .accepted
                }
        }.count
    }

    private func submit() {
        guard !model.isMutating else { return }
        handleFocused = false
        Task { await model.submitExactHandle(handle) }
    }
}
