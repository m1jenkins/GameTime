import SwiftUI

/// Exact handles only — GameTime offers no fuzzy or enumerable people search.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var handle = ""
    @FocusState private var handleFocused: Bool

    var body: some View {
        GlassArenaScreenScaffold(
            screen: .today,
            identifier: "screen.friends",
            spacing: 13
        ) {
            Text("Friends")
                .font(GlassArenaFont.display(33, .heavy))
                .foregroundStyle(GlassArena.ink)
                .padding(.horizontal, 4)

            searchCard

            if case .failed(let message) = model.loadState {
                GlassRetryRow(message: message) {
                    Task { await model.refresh() }
                }
            }

            if let result = model.exactHandleResult {
                foundCard(result)
            } else if let submitted = model.lastSubmittedHandle,
                ExactHandleSubmission.normalized(submitted) != nil,
                !model.isMutating
            {
                noMatchCard(submitted)
            }

            if !model.incomingFriendships.isEmpty {
                SectionEyebrow(text: "Wants in")
                    .padding(.leading, 8)
                ForEach(model.incomingFriendships) { card in
                    RosterRow(
                        displayName: card.displayName,
                        handle: card.handle,
                        actionTitle: "Accept",
                        isEnabled: !model.isMutating,
                        action: {
                            Task {
                                await model.acceptFriendship(
                                    with: card.otherUserID
                                )
                            }
                        },
                        tap: {
                            router.friendsPath.append(
                                .profile(card.otherUserID)
                            )
                        }
                    )
                }
            }

            if !model.outgoingFriendships.isEmpty {
                SectionEyebrow(text: "Left on read")
                    .padding(.leading, 8)
                ForEach(model.outgoingFriendships) { card in
                    RosterRow(
                        displayName: card.displayName,
                        handle: card.handle,
                        side: .neutral,
                        actionTitle: "Cancel",
                        isDestructiveAction: true,
                        isEnabled: !model.isMutating,
                        action: {
                            Task {
                                await model.removeFriendship(
                                    with: card.otherUserID
                                )
                            }
                        }
                    )
                }
            }

            if !model.acceptedFriendships.isEmpty {
                SectionEyebrow(text: "Your roster")
                    .padding(.leading, 8)
                ForEach(model.acceptedFriendships) { card in
                    RosterRow(
                        displayName: card.displayName,
                        handle: card.handle,
                        actionTitle: "Duel",
                        isEnabled: model.canStartDuel,
                        action: {
                            router.presentedSheet = .createDuel
                        },
                        tap: {
                            router.friendsPath.append(
                                .profile(card.otherUserID)
                            )
                        }
                    )
                }
            }

            if model.friendshipCards.isEmpty, model.loadState != .loading {
                EmptyDuelsCard(
                    title: "Nobody here yet.",
                    message:
                        "Ask for someone's exact handle and send the request. There is no directory to browse."
                )
            }
        }
    }

    // MARK: Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("@")
                        .font(GlassArenaFont.text(16, .semibold))
                        .foregroundStyle(GlassArena.mutedLight)
                    TextField("handle", text: $handle)
                        .font(GlassArenaFont.text(16, .medium))
                        .foregroundStyle(GlassArena.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($handleFocused)
                        .submitLabel(.search)
                        .onSubmit(submit)
                        .accessibilityIdentifier("friends.exact-handle")
                        .accessibilityLabel("Exact handle")
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassPane(.standard, cornerRadius: 16)

                Button(action: submit) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(GlassArena.tealInk)
                        .frame(width: 52, height: 48)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                            .fill(GlassArena.tealButton)
                            .shadow(
                                color: GlassArena.teal800.opacity(0.5),
                                radius: 12,
                                y: 10
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    model.isMutating
                        || ExactHandleSubmission.normalized(handle) == nil
                )
                .accessibilityIdentifier("friends.find")
                .accessibilityLabel("Find this handle")
            }

            Text(
                "Exact handles only. No fuzzy search, and nobody else's roster is browsable."
            )
            .font(GlassArenaFont.text(12))
            .foregroundStyle(GlassArena.mutedLight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPane(.hero, cornerRadius: 28)
    }

    private func foundCard(_ result: ProfileCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Exact match", fontSize: 11, tracking: 0.9)
            HStack(spacing: 12) {
                GlassAvatar(
                    initials: result.initials,
                    size: 44,
                    side: .them
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.displayName)
                        .font(GlassArenaFont.text(16, .bold))
                        .foregroundStyle(GlassArena.ink)
                    Text("@\(result.handle)")
                        .font(GlassArenaFont.text(13))
                        .foregroundStyle(GlassArena.mutedLight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                exactMatchAction(result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPane(
            .standard,
            cornerRadius: 28,
            borderColor: GlassArena.teal700.opacity(0.4)
        )
    }

    private func noMatchCard(_ submitted: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GlassArena.mutedLight)
            Text("Nothing matched @\(submitted) exactly.")
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPane(.recessed, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func exactMatchAction(_ result: ProfileCard) -> some View {
        if result.id == model.userID {
            Text("That's you")
                .font(GlassArenaFont.text(13, .semibold))
                .foregroundStyle(GlassArena.mutedLight)
        } else if let existing = model.friendshipCards.first(
            where: { $0.otherUserID == result.id }
        ) {
            Text(existing.status == .accepted ? "On your roster" : "Pending")
                .font(GlassArenaFont.text(12, .bold))
                .foregroundStyle(
                    existing.status == .accepted
                        ? GlassArena.teal900
                        : GlassArena.amber800
                )
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        (existing.status == .accepted
                            ? GlassArena.teal700
                            : GlassArena.amber400).opacity(0.16)
                    )
                )
        } else {
            Button {
                Task { await model.requestFriendship(with: result.id) }
            } label: {
                TealChip(text: "Add")
            }
            .buttonStyle(.plain)
            .disabled(model.isMutating)
            .accessibilityLabel("Add \(result.displayName)")
        }
    }

    private func submit() {
        guard !model.isMutating else { return }
        handleFocused = false
        Task { await model.submitExactHandle(handle) }
    }
}
