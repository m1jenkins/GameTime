import Foundation
import Observation

/// Owns the signed-in person's friends list and their friend commands.
/// Modeled on ChallengeV1Store: every await is fenced by an actor generation
/// and a fresh auth check, and each command is saved to a per-account journal
/// before it is sent, so a retry reuses the same request ID.
@MainActor @Observable final class FriendsStore {
    private(set) var actor: UUID?
    private(set) var list: FriendList?
    /// Device time of the last list this phone received, for "last saved" copy.
    private(set) var savedAt: Date?
    private(set) var fresh = false
    private(set) var refreshing = false
    private(set) var loadError: String?
    private(set) var pending: FriendCommand?
    private(set) var busy = false
    private(set) var actionError: String?
    private(set) var actionErrorCode: String?
    /// A short confirmation of the last change, shown once and then cleared.
    private(set) var notice: String?
    private(set) var dismissed: Set<String> = []
    private var visible = true
    private var generation = UUID()
    private var refreshGeneration = UUID()
    private let auth: any AuthClient
    let client: any FriendCommandsClient
    let journal: FriendJournal
    private let clock: @MainActor () -> Date

    init(auth: any AuthClient, client: any FriendCommandsClient, journal: FriendJournal,
         clock: @escaping @MainActor () -> Date = { Date() }) {
        self.auth = auth; self.client = client; self.journal = journal; self.clock = clock
    }

    enum ListState: Equatable { case loading, loaded, offline, unavailable }
    var state: ListState {
        if list != nil { return fresh ? .loaded : .offline }
        if refreshing || (loadError == nil && actor != nil) { return .loading }
        return .unavailable
    }
    var friends: [FriendPerson] { list?.friends ?? [] }
    var incoming: [FriendPerson] { list?.incoming ?? [] }
    var outgoing: [FriendPerson] { list?.outgoing ?? [] }
    var blocked: [FriendPerson] { list?.blocked ?? [] }
    var canAct: Bool { actor != nil && fresh && !busy && pending == nil }

    /// Friends who accepted a request you sent within the last week, until you
    /// dismiss the row on this phone. There is no count and no badge.
    var recentlyAccepted: [FriendPerson] {
        guard let list else { return [] }
        let horizon = list.serverTime.date.addingTimeInterval(-7 * 86_400)
        return list.friends
            .filter { $0.youAsked == true && ($0.since?.date ?? .distantPast) > horizon && !dismissed.contains(Self.acceptanceKey($0)) }
            .sorted { ($0.since?.date ?? .distantPast) > ($1.since?.date ?? .distantPast) }
    }
    static func acceptanceKey(_ person: FriendPerson) -> String {
        person.id.uuidString.lowercased() + "|" + (person.since?.rawValue ?? "")
    }

    func setActor(_ actor: UUID?) {
        self.actor = actor; visible = true; generation = UUID(); refreshGeneration = UUID()
        list = nil; savedAt = nil; fresh = false; refreshing = false; loadError = nil
        pending = nil; busy = false; actionError = nil; actionErrorCode = nil; notice = nil; dismissed = []
    }
    func hide() { visible = false; refreshGeneration = UUID(); refreshing = false; fresh = false }
    func show() async { visible = true; await refresh() }
    func clearNotice() { notice = nil }
    func clearActionError() { actionError = nil; actionErrorCode = nil }

    func refresh() async {
        guard visible, let actor else { return }
        let ticket = generation; let token = UUID(); refreshGeneration = token
        refreshing = true
        defer { if ticket == generation, token == refreshGeneration { refreshing = false } }
        let authenticated = await auth.currentUserID()
        guard ticket == generation, token == refreshGeneration else { return }
        guard authenticated == actor else { setActor(nil); return }
        do {
            let entry = try await journal.load(actor)
            guard ticket == generation, token == refreshGeneration else { return }
            pending = entry.pending; dismissed = Set(entry.dismissed)
        } catch {
            guard ticket == generation, token == refreshGeneration else { return }
            actionError = FriendsCopy.message(for: error)
        }
        do {
            let loaded = try await client.friendList(actor: actor)
            let finalActor = await auth.currentUserID()
            guard ticket == generation, token == refreshGeneration else { return }
            guard finalActor == actor else { setActor(nil); return }
            list = loaded; savedAt = clock(); fresh = true; loadError = nil
        } catch {
            guard ticket == generation, token == refreshGeneration else { return }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil); return }
            fresh = false; loadError = FriendsCopy.message(for: error)
        }
    }

    enum LookupOutcome: Equatable {
        case found(FriendPerson, FriendLookup.Relation)
        case notFound(String)
        case failed(String)
    }
    /// Exact-username lookup. Blocked, suspended and deleted accounts look the
    /// same as a username that doesn't exist.
    func lookup(_ input: String) async -> LookupOutcome? {
        guard let actor else { return nil }
        guard let username = ExactHandleSubmission.normalized(input) else {
            return .notFound(String(input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("@")))
        }
        let ticket = generation
        do {
            let result = try await client.friendLookup(username, actor: actor)
            let authenticated = await auth.currentUserID()
            guard ticket == generation else { return nil }
            guard authenticated == actor else { setActor(nil); return nil }
            guard let person = result.person, let relation = result.relation else { return .notFound(username) }
            return .found(person, relation)
        } catch {
            guard ticket == generation else { return nil }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil); return nil }
            return .failed(FriendsCopy.message(for: error))
        }
    }

    @discardableResult
    func perform(_ op: FriendCommand.Op, person: FriendPerson, reason: FriendCommand.Reason? = nil) async -> Bool {
        guard let actor, !busy, pending == nil, person.id != actor else { return false }
        return await send(FriendCommand(actor: actor, op: op, person: person, reason: reason))
    }
    @discardableResult
    func retry() async -> Bool {
        guard let pending, !busy else { return false }
        return await send(pending)
    }
    /// Stops waiting for a saved change on this phone. The server list decides
    /// what actually happened, so refresh right after.
    func discardPending() async {
        guard let pending, !busy else { return }
        let ticket = generation
        do { try await journal.removePending(pending) }
        catch { if ticket == generation { actionError = FriendsCopy.message(for: error) }; return }
        guard ticket == generation else { return }
        self.pending = nil; actionError = nil; actionErrorCode = nil
        await refresh()
    }
    func dismissAccepted(_ person: FriendPerson) async {
        guard let actor else { return }
        let key = Self.acceptanceKey(person); let ticket = generation
        dismissed.insert(key)
        do { try await journal.dismiss(key, actor: actor) }
        catch { if ticket == generation { actionError = FriendsCopy.message(for: error) } }
    }

    private func send(_ command: FriendCommand) async -> Bool {
        guard command.actorId == actor else { return false }
        let ticket = generation; busy = true; actionError = nil; actionErrorCode = nil; notice = nil
        defer { if ticket == generation { busy = false } }
        do {
            try await journal.savePending(command)
            guard ticket == generation else { return false }
            pending = command
            let receipt = try await client.friendCommand(command)
            guard ticket == generation else { return false }
            guard receipt.matches(command.op) else { throw ChallengeV1Error.invalidResponse }
            try await journal.removePending(command)
            guard ticket == generation else { return false }
            pending = nil
            apply(command)
            notice = FriendsCopy.done(command)
            busy = false
            await refresh()
            return ticket == generation
        } catch {
            guard ticket == generation else { return false }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil); return false }
            if case .server(let code) = error as? ChallengeV1Error {
                // The server answered, so retrying the same request can't help.
                try? await journal.removePending(command)
                guard ticket == generation else { return false }
                pending = nil
                actionError = FriendsCopy.message(for: error, username: command.username)
                actionErrorCode = code
                busy = false
                await refresh()
            } else {
                actionError = FriendsCopy.message(for: error)
            }
            return false
        }
    }

    /// Shows a confirmed change right away. The refresh that follows replaces it.
    private func apply(_ command: FriendCommand) {
        guard var list else { return }
        let id = command.subject
        func drop(_ people: inout [FriendPerson]) -> FriendPerson? {
            guard let index = people.firstIndex(where: { $0.id == id }) else { return nil }
            return people.remove(at: index)
        }
        switch command.op {
        case .request:
            if !list.outgoing.contains(where: { $0.id == id }) { list.outgoing.insert(command.person, at: 0) }
        case .accept:
            var person = drop(&list.incoming) ?? command.person
            person.youAsked = false; person.since = list.serverTime
            list.friends.append(person)
        case .decline: _ = drop(&list.incoming)
        case .cancel: _ = drop(&list.outgoing)
        case .remove: _ = drop(&list.friends)
        case .block:
            _ = drop(&list.friends); _ = drop(&list.incoming); _ = drop(&list.outgoing)
            if !list.blocked.contains(where: { $0.id == id }) { list.blocked.insert(command.person, at: 0) }
        case .unblock: _ = drop(&list.blocked)
        case .report: break
        }
        self.list = list
    }
}
