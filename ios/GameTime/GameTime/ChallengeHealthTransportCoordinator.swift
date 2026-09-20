import Foundation
import GameTimeCore

/// One app-lifetime lease for every endpoint using the app's App Attest signer.
/// Endpoint owners still encode, send, validate and acknowledge their own bytes.
/// Recovery metadata is local only; it is never a replacement wire envelope.
@MainActor
final class ChallengeHealthTransportCoordinator {
  enum Kind: String, CaseIterable { case upload, readiness, metrics, coverage, diagnostic }
  enum Failure: LocalizedError, Equatable {
    case busy, accountChanged, missingWriter, malformedAssertion, counterConflict, pendingDelivery
    var errorDescription: String? {
      switch self {
      case .busy: "We’re already updating your activity. Try again in a moment."
      case .accountChanged: "Your sign-in changed. Open your challenge and try again."
      default: "We couldn’t finish a saved activity update. Refresh your challenge and try again."
      }
    }
  }

  struct Pending {
    let kind: Kind
    let id: UUID
    let keyID: String
    let assertion: Data
    let body: Data
    let deliver: @MainActor () async throws -> Void
  }

  let uploadStore: ChallengeHealthUploadFileStore
  let readinessStore: ChallengeHealthReadinessFileStore
  private let binding: (@MainActor () -> WeeklyClientSession?)?
  private let prepareSession: @MainActor (UUID) async throws -> Void
  private var loaders: [Kind: @MainActor (UUID) async throws -> [Pending]] = [:]
  private var recoveredCounters: [String: UInt32] = [:]
  private var leasedActor: UUID?
  private var session: WeeklyClientSession?
  private var generation = UUID()
  private var leaseGeneration: UUID?

  init(uploadStore: ChallengeHealthUploadFileStore,
       readinessStore: ChallengeHealthReadinessFileStore,
       binding: (@MainActor () -> WeeklyClientSession?)? = nil,
       prepareSession: @escaping @MainActor (UUID) async throws -> Void = { _ in }) {
    self.uploadStore = uploadStore; self.readinessStore = readinessStore
    self.binding = binding; self.prepareSession = prepareSession
  }

  static func sessionID(_ token: String) -> UUID? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    value += String(repeating: "=", count: (4 - value.count % 4) % 4)
    guard let data = Data(base64Encoded: value), let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = body["session_id"] as? String else { return nil }
    return UUID(uuidString: id)
  }

  func register(_ kind: Kind, load: @escaping @MainActor (UUID) async throws -> [Pending]) {
    precondition(loaders[kind] == nil, "A signed writer must have exactly one app-lifetime owner")
    loaders[kind] = load
  }

  func acquire(actor: UUID) -> Bool {
    guard leasedActor == nil else { return false }
    leasedActor = actor; leaseGeneration = generation; session = binding?()
    return true
  }

  func begin(actor: UUID) async throws {
    guard acquire(actor: actor) else { throw Failure.busy }
    do {
      try await prepareSession(actor)
      // The preparation service fences the authenticated session across refresh.
      session = binding?()
      try check(actor: actor)
    } catch { release(actor: actor); throw error }
  }

  func release(actor: UUID) {
    guard leasedActor == actor else { return }
    leasedActor = nil; session = nil; leaseGeneration = nil
  }

  func invalidate() { generation = UUID() }

  func check(actor: UUID) throws {
    try Task.checkCancellation()
    guard leasedActor == actor, leaseGeneration == generation else { throw Failure.accountChanged }
    if let binding {
      guard let session, session.actorID == actor, binding() == session else { throw Failure.accountChanged }
    }
  }

  func validateNewSignature(keyID: String, assertion: Data) throws {
    guard !keyID.isEmpty, let counter = try? AssertionCounterDecoder.decode(from: assertion), counter > 0 else {
      throw Failure.malformedAssertion
    }
    guard counter > (recoveredCounters[keyID] ?? 0) else { throw Failure.counterConflict }
    // A persisted signature can fail delivery; the next operation must recover
    // its journal before this counter can be passed. Unsaved signatures leave gaps.
    recoveredCounters[keyID] = counter
  }

  /// Reload every journal after acquiring the lease. Validate the entire set
  /// before delivery, then recover in counter order per key. Gaps are permitted.
  @discardableResult
  func recover(actor: UUID) async throws -> [Pending] {
    try check(actor: actor)
    if loaders[.upload] == nil, !(try uploadStore.load(actor: actor).pending).isEmpty { throw Failure.missingWriter }
    if loaders[.readiness] == nil, !(try readinessStore.load(actor: actor).pending).isEmpty { throw Failure.missingWriter }
    var ordered: [(Pending, UInt32)] = []
    for kind in Kind.allCases {
      guard let load = loaders[kind] else { continue }
      let records = try await load(actor)
      try check(actor: actor)
      for record in records {
        guard record.kind == kind, !record.keyID.isEmpty,
              let counter = try? AssertionCounterDecoder.decode(from: record.assertion), counter > 0 else {
          throw Failure.malformedAssertion
        }
        ordered.append((record, counter))
      }
    }
    ordered.sort { $0.0.keyID == $1.0.keyID ? $0.1 < $1.1 : $0.0.keyID < $1.0.keyID }
    for index in ordered.indices.dropFirst() {
      let (previous, counter) = ordered[index - 1], (current, next) = ordered[index]
      if previous.keyID == current.keyID && counter == next {
        guard previous.kind == current.kind, previous.id == current.id,
              previous.body == current.body, previous.assertion == current.assertion else { throw Failure.counterConflict }
      }
    }
    var recovered: [Pending] = []
    var deliveredCounters: Set<String> = []
    for (record, counter) in ordered {
      guard deliveredCounters.insert(record.keyID + ":" + String(counter)).inserted else { continue }
      try check(actor: actor)
      try await record.deliver()
      try check(actor: actor)
      recoveredCounters[record.keyID] = max(counter, recoveredCounters[record.keyID] ?? 0)
      recovered.append(record)
    }
    return recovered
  }
}
