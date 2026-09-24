import SwiftUI
import UIKit

/// D142 friends under You. Every request is deliberate and by exact username:
/// no suggestions, contacts or counts. Decline, remove, block and report never
/// notify the other person. Copy follows the approved Phase 1 mocks.

/// One row under your profile on You. It shows no count or badge.
struct FriendsEntryRow: View {
    let challenges: ChallengeV1Store
    let username: String?
    var body: some View {
        NavigationLink { FriendsView(challenges: challenges, username: username) } label: {
            HStack(spacing: 13) {
                LiveIconTile(symbol: "person.2")
                Text("Friends").liveFont(16, weight: .medium)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SignalTheme.textSecondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(SignalTheme.textPrimary)
        .modifier(LiveCardModifier(radius: 18, material: true))
        .accessibilityIdentifier("profile.friends")
    }
}

struct FriendsView: View {
    let challenges: ChallengeV1Store
    let username: String?
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var sharing = false
    @State private var selected: FriendPerson?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LivePageHeader(title: "Friends", back: { dismiss() }) {
                    Button { adding = true } label: {
                        Image(systemName: "person.badge.plus").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(SignalTheme.textPrimary)
                    .disabled(friends?.canAct != true)
                    .accessibilityLabel("Add a friend").accessibilityIdentifier("friends.add")
                }
                if let friends { content(friends) }
                else { FriendsUnavailableCard(message: "Friends aren’t available right now. Try again later.", retry: nil) }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
        }
        .background(SignalTheme.canvas.ignoresSafeArea())
        .foregroundStyle(SignalTheme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await friends?.refresh() }
        .task { await friends?.refresh() }
        .modifier(FriendsNoticeToast(friends: friends))
        .sheet(isPresented: $adding) { AddFriendView(challenges: challenges, username: username) }
        .sheet(item: $selected) { person in FriendActionsSheet(person: person) }
        .onChange(of: friends?.actor) { adding = false; selected = nil }
    }

    @ViewBuilder private func content(_ friends: FriendsStore) -> some View {
        switch friends.state {
        case .loading:
            FriendsLoadingList()
        case .unavailable:
            if friends.offline {
                FriendsBanner(title: "You’re offline", text: "Connect to see your friends and requests.")
                    .padding(.top, 8)
                Button("Try again") { Task { await friends.refresh() } }
                    .buttonStyle(LiveSecondaryButtonStyle()).padding(.top, 22)
            } else {
                FriendsUnavailableCard(message: friends.loadError ?? "We couldn’t load your friends. Try again.",
                                       retry: { Task { await friends.refresh() } })
            }
        case .loaded, .offline:
            if friends.state == .offline {
                FriendsBanner(title: friends.offline ? "You’re offline" : "We couldn’t refresh your friends",
                              text: "This is your last saved list" + (friends.savedAt.map { ", from \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
                                + ". Connect to accept requests or add friends.")
                    .padding(.top, 8)
            }
            FriendsActionStatus(friends: friends).padding(.top, 8)
            if friends.incoming.isEmpty && friends.friends.isEmpty && friends.outgoing.isEmpty {
                empty(friends)
            } else {
                lists(friends)
            }
            if friends.state == .offline {
                Button("Try again") { Task { await friends.refresh() } }
                    .buttonStyle(LiveSecondaryButtonStyle()).padding(.top, 22)
            }
        }
    }

    @ViewBuilder private func lists(_ friends: FriendsStore) -> some View {
        if !friends.incoming.isEmpty {
            LiveSectionHeader(title: "Requests for you").padding(.top, 8)
            LiveListCard {
                ForEach(friends.incoming) { person in
                    FriendRow(person: person) {
                        HStack(spacing: 8) {
                            Button("Decline") { Task { await friends.perform(.decline, person: person) } }
                                .buttonStyle(LivePillButtonStyle(kind: .quiet))
                                .accessibilityLabel("Decline \(person.displayName)’s request")
                            Button("Accept") { Task { await friends.perform(.accept, person: person) } }
                                .buttonStyle(LivePillButtonStyle(kind: .filled))
                                .accessibilityLabel("Accept \(person.displayName)’s request")
                        }.disabled(!friends.canAct)
                    }
                }
            }
            LiveCaption("If you decline, the request goes away. We don’t tell them.").padding(.top, 8)
        }
        LiveSectionHeader(title: "Friends")
        if friends.friends.isEmpty {
            Text("No friends yet.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        } else {
            LiveListCard {
                ForEach(friends.friends) { person in
                    Button { selected = person } label: {
                        FriendRow(person: person) {
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SignalTheme.textSecondary).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Remove, block or report")
                }
            }
        }
        if !friends.outgoing.isEmpty {
            LiveSectionHeader(title: "Requests you sent")
            LiveListCard {
                ForEach(friends.outgoing) { person in
                    FriendRow(person: person, detail: "@\(person.username) · " + FriendsDates.sent(person.sentAt, now: friends.list?.serverTime)) {
                        Button("Cancel") { Task { await friends.perform(.cancel, person: person) } }
                            .buttonStyle(LivePillButtonStyle(kind: .text)).disabled(!friends.canAct)
                            .accessibilityLabel("Cancel your request to \(person.displayName)")
                    }
                }
            }
        }
        LiveListCard {
            Button { adding = true } label: {
                LiveNavRow(symbol: "person.badge.plus", title: "Add a friend", accent: true, chevron: false)
            }
            .buttonStyle(.plain).disabled(!friends.canAct).accessibilityIdentifier("friends.add.row")
            NavigationLink { BlockedPeopleView() } label: {
                LiveNavRow(symbol: "hand.raised", title: "Blocked people")
            }
            .buttonStyle(.plain).accessibilityIdentifier("friends.blocked")
        }
        .padding(.top, 28)
        LiveCaption("Only you see your friends list.").padding(.top, 12)
    }

    @ViewBuilder private func empty(_ friends: FriendsStore) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2").font(.system(size: 28, weight: .regular))
                .foregroundStyle(SignalTheme.textSecondary)
                .frame(width: 64, height: 64).background(SignalTheme.soft, in: Circle())
                .accessibilityHidden(true)
            Text("Add your first friend").liveFont(21, weight: .bold).tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Text("Friends can invite each other to challenges. Ask them for their GameTime username, then send a request.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.top, 36)
        VStack(spacing: 10) {
            Button { adding = true } label: { Label("Add a friend", systemImage: "person.badge.plus") }
                .buttonStyle(LivePrimaryButtonStyle()).disabled(!friends.canAct)
                .accessibilityIdentifier("friends.empty.add")
            if let username {
                ShareLink(item: FriendsShare.sentence(username)) { Label("Share your username", systemImage: "square.and.arrow.up") }
                    .buttonStyle(LiveSecondaryButtonStyle())
            }
        }.padding(.top, 22)
        LiveCaption("We don’t suggest people or read your contacts.")
            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 16)
        if !friends.blocked.isEmpty {
            LiveListCard {
                NavigationLink { BlockedPeopleView() } label: { LiveNavRow(symbol: "hand.raised", title: "Blocked people") }
                    .buttonStyle(.plain)
            }.padding(.top, 28)
        }
    }
}

// MARK: Add a friend

struct AddFriendView: View {
    let challenges: ChallengeV1Store
    let username: String?
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddFriendLookup()
    @State private var ageConfirmed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Enter your friend’s exact username. They’ll need to accept before you can invite them to a challenge.")
                        .liveFont(15).foregroundStyle(SignalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    if challenges.access?.ageConfirmed == false { ageCard.padding(.top, 18) }
                    FriendUsernameField(text: $model.query, focused: $focused, action: "Find", enabled: canSearch) {
                        Task { await find() }
                    }
                    .padding(.top, 20)
                    if let friends { result(friends).padding(.top, 14) }
                    if let username { yourUsername(username).padding(.top, 28) }
                }
                .padding(.horizontal, 20).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SignalTheme.canvas.ignoresSafeArea())
            .foregroundStyle(SignalTheme.textPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SignalCreationChrome(title: "Add a friend", showsBack: false, back: {}, close: { dismiss() })
            }
            .modifier(FriendsNoticeToast(friends: friends, showsRequestNotice: false))
            .onAppear { focused = true }
            .onChange(of: friends?.actor) { dismiss() }
        }
        .tint(SignalTheme.accent)
    }

    private var canSearch: Bool {
        friends?.actor != nil && !model.searching && ExactHandleSubmission.normalized(model.query) != nil
    }

    private func find() async {
        guard let friends, canSearch else { return }
        focused = false
        await model.find(in: friends)
    }

    @ViewBuilder private func result(_ friends: FriendsStore) -> some View {
        if model.searching {
            ProgressView("Looking for @\(model.searched ?? "")…").font(.subheadline)
        } else if let outcome = model.outcome {
            switch outcome {
            case .found(let person, let relation):
                found(person, relation: relation, friends: friends)
            case .notFound(let name):
                FriendsMessage(text: "We couldn’t find @\(name). Usernames need to match exactly — check the spelling with your friend.", warning: true)
            case .failed(let text):
                FriendsMessage(text: text, warning: true)
            }
        }
    }

    @ViewBuilder private func found(_ person: FriendPerson, relation: FriendLookup.Relation, friends: FriendsStore) -> some View {
        switch relation {
        case .none:
            VStack(alignment: .leading, spacing: 10) {
                FriendRow(person: person) {
                    if model.sent == person.id {
                        Label("Sent", systemImage: "checkmark").liveFont(14, weight: .semibold)
                            .foregroundStyle(SignalTheme.textSecondary).padding(.horizontal, 14).frame(minHeight: 44)
                    } else {
                        Button("Send request") { Task { await model.send(person, in: friends) } }
                            .buttonStyle(LivePillButtonStyle(kind: .filled)).disabled(!friends.canAct)
                            .accessibilityIdentifier("friends.add.send")
                    }
                }
                .modifier(LiveSurfaceCard())
                if model.sent == person.id {
                    FriendsMessage(text: "Request sent. \(person.firstName) will see it in GameTime and can accept or decline.")
                } else if let error = model.error {
                    FriendsMessage(text: error, warning: true)
                }
            }
        case .friends:
            FriendRow(person: person, detail: "@\(person.username) · Already your friend") { EmptyView() }
                .modifier(LiveSurfaceCard())
        case .incoming:
            VStack(alignment: .leading, spacing: 12) {
                FriendRow(person: person) { EmptyView() }
                if model.accepted == person.id {
                    FriendsMessage(text: "You and \(person.firstName) are now friends.")
                } else if model.declined == person.id {
                    FriendsMessage(text: "Request declined.")
                } else {
                    Text("\(person.username) already sent you a request. Accept it to become friends.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Decline") { Task { await model.answer(.decline, person, in: friends) } }
                            .buttonStyle(LivePillButtonStyle(kind: .quiet))
                        Button("Accept") { Task { await model.answer(.accept, person, in: friends) } }
                            .buttonStyle(LivePillButtonStyle(kind: .filled))
                    }.disabled(!friends.canAct)
                    if let error = model.error { FriendsMessage(text: error, warning: true) }
                }
            }
            .padding(.bottom, 4).modifier(LiveSurfaceCard())
        case .outgoing:
            FriendsMessage(text: "You already sent @\(person.username) a request. You can cancel it from Friends.")
        case .you:
            FriendsMessage(text: "That’s your username. Ask your friend for theirs.")
        }
    }

    private var ageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm your age to add friends").liveFont(15, weight: .semibold)
            Toggle("I confirm I am 21 or older", isOn: $ageConfirmed).font(.subheadline).tint(SignalTheme.accent)
            Button("Save") { Task { await challenges.submit(op: "confirm_age", fields: ["confirmed": .bool(true)]) } }
                .buttonStyle(LivePrimaryButtonStyle(height: 46))
                .disabled(!ageConfirmed || challenges.busy || challenges.pending != nil)
        }
        .padding(16).modifier(LiveCardModifier(radius: 18, material: true))
    }

    private func yourUsername(_ username: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(SignalTheme.divider).padding(.bottom, 14)
            Text("Your username").liveFont(13, weight: .medium).foregroundStyle(SignalTheme.textSecondary)
            HStack(spacing: 10) {
                Text("@\(username)").liveFont(20, weight: .bold).tracking(-0.5)
                    .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = "@\(username)"
                    model.copied = true
                    SignalAccessibility.announce("Username copied.")
                } label: {
                    Image(systemName: model.copied ? "checkmark" : "doc.on.doc").font(.system(size: 17)).frame(width: 44, height: 44)
                        .background(SignalTheme.soft, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Copy username")
                ShareLink(item: FriendsShare.sentence(username)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17)).frame(width: 44, height: 44)
                        .background(SignalTheme.soft, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Share username")
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 8)
            .modifier(LiveCardModifier(radius: 18))
            LiveCaption(model.copied ? "Username copied." : "Send it to a friend so they can add you.")
        }
    }
}

/// The lookup form's local state. The store owns every request and retry.
@MainActor @Observable final class AddFriendLookup {
    var query = "" { didSet { if query != oldValue { copied = false } } }
    var copied = false
    private(set) var searching = false
    private(set) var searched: String?
    private(set) var outcome: FriendsStore.LookupOutcome?
    private(set) var sent: UUID?
    private(set) var accepted: UUID?
    private(set) var declined: UUID?
    private(set) var error: String?

    func find(in friends: FriendsStore) async {
        guard !searching else { return }
        searching = true; searched = ExactHandleSubmission.normalized(query); error = nil
        sent = nil; accepted = nil; declined = nil
        defer { searching = false }
        outcome = await friends.lookup(query)
    }

    func send(_ person: FriendPerson, in friends: FriendsStore) async {
        error = nil
        if await friends.perform(.request, person: person) { sent = person.id; return }
        // They asked you first: offer their request instead of a second one.
        if friends.actionErrorCode == "friend_incoming_request_exists" {
            outcome = .found(person, .incoming); friends.clearActionError()
        } else {
            error = friends.actionError
        }
    }

    func answer(_ op: FriendCommand.Op, _ person: FriendPerson, in friends: FriendsStore) async {
        error = nil
        guard await friends.perform(op, person: person) else { error = friends.actionError; return }
        if op == .accept { accepted = person.id } else { declined = person.id }
    }
}

enum FriendsShare {
    /// One plain sentence for the system share sheet, with no link.
    static func sentence(_ username: String) -> String { "I’m @\(username) on GameTime. Add me as a friend." }
}

// MARK: Safety

struct FriendActionsSheet: View {
    let person: FriendPerson
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: FriendCommand.Op?
    @State private var reporting = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                LiveAvatar(username: person.displayName, size: 72)
                Text(person.displayName).liveFont(22, weight: .bold).tracking(-0.6).padding(.top, 12)
                Text("@\(person.username)" + (person.since.map { " · Friends since " + FriendsDates.since($0, now: friends?.list?.serverTime) } ?? ""))
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 20)
            .accessibilityElement(children: .combine)
            LiveListCard {
                Button { confirming = .remove } label: { LiveNavRow(symbol: "person.badge.minus", title: "Remove friend", chevron: false) }
                    .buttonStyle(.plain).accessibilityIdentifier("friends.remove")
                Button { confirming = .block } label: { LiveNavRow(symbol: "hand.raised", title: "Block", chevron: false) }
                    .buttonStyle(.plain).accessibilityIdentifier("friends.block")
                Button { reporting = true } label: { LiveNavRow(symbol: "flag", title: "Report", chevron: false) }
                    .buttonStyle(.plain).accessibilityIdentifier("friends.report")
            }
            .disabled(friends?.canAct != true)
            LiveCaption("We don’t send a notice when you remove, block or report someone.")
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            if let error = friends?.actionError { FriendsMessage(text: error, warning: true).padding(.top, 10) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(SignalTheme.canvas.ignoresSafeArea())
        .foregroundStyle(SignalTheme.textPrimary)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .modifier(FriendConfirmation(person: person, op: $confirming) { op in
            guard let friends else { return }
            if await friends.perform(op, person: person) { dismiss() }
        })
        .sheet(isPresented: $reporting) { ReportFriendSheet(person: person, onBlocked: { dismiss() }) }
        .onChange(of: friends?.actor) { dismiss() }
    }
}

/// The confirmation for Remove, Block and Unblock says exactly what changes.
struct FriendConfirmation: ViewModifier {
    let person: FriendPerson
    @Binding var op: FriendCommand.Op?
    let perform: (FriendCommand.Op) async -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { op != nil }, set: { if !$0 { op = nil } })) {
            if let current = op {
                Button(confirm(current), role: current == .unblock ? nil : .destructive) {
                    Task { await perform(current) }
                }
            }
            Button("Cancel", role: .cancel) { op = nil }
        } message: { Text(message) }
    }

    private var name: String { person.firstName }
    private var title: String {
        switch op { case .remove: "Remove \(name)?"; case .block: "Block \(name)?"; case .unblock: "Unblock \(name)?"; default: "" }
    }
    private func confirm(_ op: FriendCommand.Op) -> String {
        switch op { case .remove: "Remove"; case .block: "Block"; default: "Unblock" }
    }
    private var message: String {
        switch op {
        case .remove: "You’ll stop being friends. Challenges you already share stay as they are."
        case .block: "\(name) won’t be able to find you or send you requests, and you’ll stop being friends. If you share a challenge that hasn’t finished, you both leave it. If fewer than two people are left, it won’t count."
        case .unblock: "\(name) will be able to find you and send you requests again. You won’t become friends unless you both agree."
        default: ""
        }
    }
}

struct ReportFriendSheet: View {
    let person: FriendPerson
    var onBlocked: () -> Void = {}
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dismiss) private var dismiss
    @State private var reason: FriendCommand.Reason?
    @State private var reported = false
    @State private var confirming: FriendCommand.Op?

    static func label(_ reason: FriendCommand.Reason) -> String {
        switch reason {
        case .username: "Their name or username"
        case .unwantedContact: "Unwanted requests or invitations"
        case .unsafeBehavior: "Something that feels unsafe"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reported { thanks } else { form }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 28)
        .background(SignalTheme.canvas.ignoresSafeArea())
        .foregroundStyle(SignalTheme.textPrimary)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .modifier(FriendConfirmation(person: person, op: $confirming) { op in
            guard let friends else { return }
            if await friends.perform(op, person: person) { dismiss(); onBlocked() }
        })
        .onChange(of: friends?.actor) { dismiss() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Report \(person.firstName)").liveFont(22, weight: .bold).tracking(-0.6)
                .accessibilityAddTraits(.isHeader)
            Text("Tell us what’s wrong. We read every report. \(person.firstName) isn’t told.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            LiveListCard {
                ForEach(FriendCommand.Reason.allCases, id: \.self) { value in
                    Button { reason = value } label: {
                        HStack(spacing: 12) {
                            Image(systemName: reason == value ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20)).foregroundStyle(reason == value ? SignalTheme.accent : SignalTheme.divider)
                                .accessibilityHidden(true)
                            Text(Self.label(value)).liveFont(15)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 54).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == value ? [.isSelected] : [])
                }
            }
            .padding(.top, 16)
            if let error = friends?.actionError { FriendsMessage(text: error, warning: true).padding(.top, 10) }
            Button("Send report") {
                guard let friends, let reason else { return }
                Task { if await friends.perform(.report, person: person, reason: reason) { reported = true } }
            }
            .buttonStyle(LivePrimaryButtonStyle()).padding(.top, 14)
            .disabled(reason == nil || friends?.canAct != true)
            .accessibilityIdentifier("friends.report.send")
        }
    }

    private var thanks: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 26, weight: .semibold)).foregroundStyle(SignalTheme.accent)
                .frame(width: 64, height: 64).background(SignalTheme.selection, in: Circle()).accessibilityHidden(true)
            Text("Thanks for telling us").liveFont(21, weight: .bold).tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Text("We’ll look into it. You can also block them.").font(.subheadline)
                .foregroundStyle(SignalTheme.textSecondary).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                if friends?.blocked.contains(where: { $0.id == person.id }) != true {
                    Button { confirming = .block } label: { Label("Block \(person.firstName)", systemImage: "hand.raised") }
                        .buttonStyle(LiveSecondaryButtonStyle()).disabled(friends?.canAct != true)
                }
                Button("Done") { dismiss() }.liveFont(15, weight: .medium)
                    .foregroundStyle(SignalTheme.textSecondary).frame(maxWidth: .infinity, minHeight: 44)
            }.padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .onAppear { SignalAccessibility.announce("Report sent.") }
    }
}

struct BlockedPeopleView: View {
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dismiss) private var dismiss
    @State private var unblocking: FriendPerson?
    @State private var confirming: FriendCommand.Op?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LivePageHeader(title: "Blocked people", back: { dismiss() })
                Text("Blocked people can’t find you or send you requests. They aren’t told.")
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                if let friends {
                    FriendsActionStatus(friends: friends).padding(.top, 8)
                    if friends.blocked.isEmpty {
                        VStack(spacing: 6) {
                            Text("No one is blocked").liveFont(17, weight: .semibold)
                            Text("You can block someone from their name in Friends, or from a challenge.")
                                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        LiveListCard {
                            ForEach(friends.blocked) { person in
                                FriendRow(person: person) {
                                    Button("Unblock") { unblocking = person; confirming = .unblock }
                                        .buttonStyle(LivePillButtonStyle(kind: .quiet)).disabled(!friends.canAct)
                                        .accessibilityLabel("Unblock \(person.displayName)")
                                }
                            }
                        }.padding(.top, 18)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
        }
        .background(SignalTheme.canvas.ignoresSafeArea())
        .foregroundStyle(SignalTheme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await friends?.refresh() }
        .modifier(FriendsNoticeToast(friends: friends))
        .modifier(FriendConfirmation(person: unblocking ?? FriendPerson(id: UUID(), username: "", displayName: ""), op: $confirming) { op in
            guard let friends, let person = unblocking else { return }
            await friends.perform(op, person: person); unblocking = nil
        })
    }
}

// MARK: Pieces

struct FriendRow<Trailing: View>: View {
    let person: FriendPerson
    var detail: String? = nil
    @ViewBuilder let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                LiveAvatar(username: person.displayName, size: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName).liveFont(16, weight: .semibold).lineLimit(2)
                    Text(detail ?? "@\(person.username)").liveFont(13).foregroundStyle(SignalTheme.textSecondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 66).contentShape(Rectangle())
    }
}

struct FriendsMessage: View {
    let text: String
    var warning = false
    var body: some View {
        Text(text).font(.subheadline)
            .foregroundStyle(warning ? SignalTheme.danger : SignalTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(warning ? "friends.message.warning" : "friends.message")
    }
}

struct FriendsBanner: View {
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.slash").font(.system(size: 17)).foregroundStyle(SignalTheme.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).liveFont(15, weight: .semibold)
                Text(text).liveFont(13).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14).background(SignalTheme.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct FriendsUnavailableCard: View {
    let message: String
    let retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We couldn’t load your friends").liveFont(18, weight: .bold).tracking(-0.4)
            Text(message).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let retry { Button("Try again", action: retry).buttonStyle(LivePrimaryButtonStyle(height: 48)) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiveCardModifier(radius: 20, material: true)).padding(.top, 8)
    }
}

struct FriendsLoadingList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveSectionHeader(title: "Friends").padding(.top, -12)
            LiveListCard {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        Circle().fill(SignalTheme.soft).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(SignalTheme.soft).frame(width: 140, height: 12)
                            Capsule().fill(SignalTheme.soft).frame(width: 90, height: 10)
                        }
                        Spacer()
                    }.padding(.horizontal, 14).frame(minHeight: 66)
                }
            }
            HStack(spacing: 8) { ProgressView(); Text("Loading your friends…") }
                .liveFont(13).foregroundStyle(SignalTheme.textSecondary).padding(.top, 14).padding(.horizontal, 4)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading your friends")
    }
}

/// A change saved on this phone but not confirmed, or a refused change.
struct FriendsActionStatus: View {
    let friends: FriendsStore
    var body: some View {
        if let pending = friends.pending {
            VStack(alignment: .leading, spacing: 10) {
                Text("We couldn’t confirm your last change").font(.subheadline.weight(.semibold))
                Text(FriendsStatusCopy.pending(pending)).font(.caption).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Retry") { Task { await friends.retry() } }.accessibilityIdentifier("friends.retry")
                    Spacer()
                    Button("Stop waiting") { Task { await friends.discardPending() } }
                }
                .font(.caption.weight(.semibold)).frame(minHeight: 44).foregroundStyle(SignalTheme.accent)
                .disabled(friends.busy)
            }
            .padding(16).modifier(LiveCardModifier(radius: 17, material: true))
        } else if let error = friends.actionError {
            FriendsMessage(text: error, warning: true)
        }
    }
}

enum FriendsStatusCopy {
    static func pending(_ command: FriendCommand) -> String {
        let action: String = switch command.op {
        case .request: "send a request to \(command.person.firstName)"
        case .accept: "accept \(command.person.firstName)’s request"
        case .decline: "decline \(command.person.firstName)’s request"
        case .cancel: "cancel your request to \(command.person.firstName)"
        case .remove: "remove \(command.person.firstName)"
        case .block: "block \(command.person.firstName)"
        case .unblock: "unblock \(command.person.firstName)"
        case .report: "report \(command.person.firstName)"
        }
        return "You asked to \(action). Retry to check whether it went through, or stop waiting and refresh your list."
    }
}

enum FriendsDates {
    static func sent(_ date: ChallengeInstant?, now: ChallengeInstant?) -> String {
        guard let date else { return "Sent" }
        return Calendar.current.isDate(date.date, inSameDayAs: now?.date ?? Date()) ? "Sent today"
            : "Sent " + date.date.formatted(.dateTime.month(.abbreviated).day())
    }
    static func since(_ date: ChallengeInstant, now: ChallengeInstant?) -> String {
        Calendar.current.isDate(date.date, inSameDayAs: now?.date ?? Date()) ? "today"
            : date.date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct FriendUsernameField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let action: String
    let enabled: Bool
    let submit: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        // Large text puts the button under the field so the field keeps the width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 6))
        layout {
            HStack(spacing: 6) {
                Text("@").liveFont(17, weight: .medium).foregroundStyle(SignalTheme.textSecondary)
                    .accessibilityHidden(true)
                TextField("username", text: $text)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    .submitLabel(.search).liveFont(17, weight: .medium)
                    .focused(focused).onSubmit { if enabled { submit() } }
                    .accessibilityLabel("Friend’s username").accessibilityIdentifier("friends.username")
            }.frame(minHeight: 54)
            Button(action, action: submit).liveFont(15, weight: .semibold)
                .foregroundStyle(enabled ? SignalTheme.accent : SignalTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44).disabled(!enabled)
                .accessibilityIdentifier("friends.username.submit")
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 54)
        .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A short confirmation at the bottom of the screen that leaves on its own.
struct FriendsNoticeToast: ViewModifier {
    let friends: FriendsStore?
    var showsRequestNotice = true
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let text = friends?.notice, showsRequestNotice || !text.hasPrefix("Request sent.") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).accessibilityHidden(true)
                    Text(text).liveFont(14, weight: .medium).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 12)
                .background(SignalTheme.textPrimary.opacity(0.92), in: Capsule())
                .padding(.horizontal, 20).padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("friends.notice")
                .task(id: text) {
                    SignalAccessibility.announce(text)
                    try? await Task.sleep(for: .seconds(2.6))
                    if friends?.notice == text { friends?.clearNotice() }
                }
            }
        }
    }
}

// MARK: Invite step

/// Sends a friend request without leaving the invite step. The challenge is
/// already saved; the new friend appears in the picker once they accept.
struct InviteAddFriendRow: View {
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @State private var open = false
    @State private var model = AddFriendLookup()
    @FocusState private var focused: Bool

    var body: some View {
        if let friends {
            VStack(alignment: .leading, spacing: 8) {
                Button { open.toggle(); if open { focused = true } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus").font(.system(size: 18)).accessibilityHidden(true)
                        Text("Add a friend by username").liveFont(15, weight: .semibold)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(SignalTheme.accent).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(open ? [.isSelected] : [])
                .accessibilityIdentifier("beta.invite.add-friend")
                if open {
                    FriendUsernameField(text: $model.query, focused: $focused, action: "Send request",
                                        enabled: friends.canAct && !model.searching && ExactHandleSubmission.normalized(model.query) != nil) {
                        Task { await send(friends) }
                    }
                    FriendsMessage(text: message.text, warning: message.warning)
                    if case .found(let person, .incoming)? = model.outcome, model.accepted != person.id {
                        Button("Accept") { Task { await model.answer(.accept, person, in: friends) } }
                            .buttonStyle(LivePillButtonStyle(kind: .filled)).disabled(!friends.canAct)
                            .accessibilityLabel("Accept \(person.displayName)’s request")
                    }
                }
            }
        }
    }

    private func send(_ friends: FriendsStore) async {
        focused = false
        await model.find(in: friends)
        if case .found(let person, .none)? = model.outcome { await model.send(person, in: friends) }
    }

    private var message: (text: String, warning: Bool) {
        guard !model.searching else { return ("Looking for @\(model.searched ?? "")…", false) }
        switch model.outcome {
        case nil: return ("They’ll need to accept before you can invite them.", false)
        case .notFound(let name):
            return ("We couldn’t find @\(name). Usernames need to match exactly — check the spelling with your friend.", true)
        case .failed(let text): return (text, true)
        case .found(let person, let relation):
            switch relation {
            case .none:
                if model.sent == person.id { return ("Request sent to \(person.displayName). They’ll appear in your list once they accept.", false) }
                return (model.error ?? "They’ll need to accept before you can invite them.", model.error != nil)
            case .friends: return ("@\(person.username) is already your friend. Choose them above.", false)
            case .incoming:
                if model.accepted == person.id { return ("You and \(person.firstName) are now friends. Choose them above.", false) }
                return (model.error ?? "\(person.username) already sent you a request. Accept it to become friends.", model.error != nil)
            case .outgoing: return ("You already sent @\(person.username) a request. They’ll appear here once they accept.", false)
            case .you: return ("That’s your username. Ask your friend for theirs.", false)
            }
        }
    }
}
