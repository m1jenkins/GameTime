import SwiftUI

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.demoMode) private var demoMode
    @State private var handle = ""
    @FocusState private var handleFocused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Exact handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($handleFocused)
                        .submitLabel(.search)
                        .onSubmit(submit)
                        .accessibilityIdentifier("friends.exact-handle")

                    Button("Find", action: submit)
                        .font(.subheadline.weight(.semibold))
                        .disabled(
                            model.isMutating
                                || ExactHandleSubmission.normalized(handle) == nil
                        )
                        .accessibilityIdentifier("friends.find")
                }
            } header: {
                Text("Find one person")
            } footer: {
                if demoMode.isActive {
                    Text(
                        "Try @david1 or @david2. Demo requests are accepted immediately so you can create a challenge."
                    )
                } else {
                    Text(
                        "Exact handles only. GameTime does not offer fuzzy or enumerable people search."
                    )
                }
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            if let result = model.exactHandleResult {
                Section("Exact match") {
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: result.initials)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.displayName)
                                .font(.headline)
                            Text("@\(result.handle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        exactMatchAction(result)
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)
                }
            } else if let submitted = model.lastSubmittedHandle,
                ExactHandleSubmission.normalized(submitted) != nil,
                !model.isMutating
            {
                Section {
                    Text("No profile matched @\(submitted) exactly.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            }

            if !model.incomingFriendships.isEmpty {
                Section("Incoming") {
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
                        .listRowBackground(
                            CompetitiveTrustTheme.raisedInk
                        )
                    }
                }
            }

            if !model.outgoingFriendships.isEmpty {
                Section("Sent") {
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
                        .listRowBackground(
                            CompetitiveTrustTheme.raisedInk
                        )
                    }
                }
            }

            if !model.acceptedFriendships.isEmpty {
                Section("Friends") {
                    ForEach(model.acceptedFriendships) { card in
                        FriendshipCardRow(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                router.friendsPath.append(
                                    .profile(card.otherUserID)
                                )
                            }
                            .listRowBackground(
                                CompetitiveTrustTheme.raisedInk
                            )
                    }
                }
            }

            if model.friendshipCards.isEmpty, model.loadState != .loading {
                EmptyTrustState(
                    title: "No relationships yet",
                    message:
                        "Submit the exact handle someone shared with you to send a request.",
                    systemImage: "person.2"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .trustScreenBackground()
        .navigationTitle("Friends")
        .refreshable {
            await model.refresh()
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
            .buttonStyle(.bordered)
            .tint(CompetitiveTrustTheme.teal)
            .accessibilityLabel("Add \(result.displayName)")
        }
    }

    private func submit() {
        guard !model.isMutating else { return }
        handleFocused = false
        Task { await model.submitExactHandle(handle) }
    }
}
