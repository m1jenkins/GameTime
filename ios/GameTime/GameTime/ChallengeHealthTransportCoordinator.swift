import Foundation

/// Coordinates the two P8 App Attest writers for one account. It never sends
/// or signs: each owner keeps its own exact-body recovery path. The lease only
/// prevents either writer from passing an empty-journal preflight while the
/// other writer is awaiting signing, persistence, or acknowledgement.
@MainActor
final class ChallengeHealthTransportCoordinator {
  enum Kind { case upload, readiness }

  /// Construct one instance from the two P8 journals and pass that same
  /// instance to both writers. The clients derive their stores from it.
  let uploadStore: ChallengeHealthUploadFileStore
  let readinessStore: ChallengeHealthReadinessFileStore
  private var leasedActors: Set<UUID> = []

  init(uploadStore: ChallengeHealthUploadFileStore,
       readinessStore: ChallengeHealthReadinessFileStore) {
    self.uploadStore = uploadStore
    self.readinessStore = readinessStore
  }

  func acquire(actor: UUID) -> Bool {
    leasedActors.insert(actor).inserted
  }

  func release(actor: UUID) {
    leasedActors.remove(actor)
  }

  func peerHasPending(actor: UUID, for kind: Kind) throws -> Bool {
    switch kind {
    case .upload:
      return !(try readinessStore.load(actor: actor).pending).isEmpty
    case .readiness:
      return !(try uploadStore.load(actor: actor).pending).isEmpty
    }
  }
}
