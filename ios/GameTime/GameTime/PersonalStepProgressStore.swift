import Foundation
import Observation

@MainActor
@Observable
final class PersonalStepProgressStore {
    private(set) var ownerID: UUID?
    private(set) var challengeID: UUID?
    private(set) var displayedProgress: PersonalDisplayedProgress?
    private(set) var isRefreshing = false
    private(set) var lastHealthError: String?
    private(set) var lastUploadError: String?

    private let reader: any PersonalHealthStepReading
    private let cache: any PersonalStepSnapshotCaching
    private let uploader: any PersonalHealthSnapshotUploading
    @ObservationIgnored private var activeChallenge: PersonalChallengeSummary?
    @ObservationIgnored private var liveSnapshot: PersonalStepSnapshot?
    @ObservationIgnored private var cachedSnapshot: PersonalStepSnapshot?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var needsTrailingRefresh = false

    init(
        reader: any PersonalHealthStepReading,
        cache: any PersonalStepSnapshotCaching,
        uploader: any PersonalHealthSnapshotUploading
    ) {
        self.reader = reader
        self.cache = cache
        self.uploader = uploader
    }

    func activate(
        ownerID: UUID?,
        challenge: PersonalChallengeSummary?
    ) async {
        let fingerprint = challenge?.termsFingerprint
        let priorOwnerID = self.ownerID
        let priorChallenge = activeChallenge
        let shouldRemovePriorCache = priorOwnerID == ownerID
            && priorChallenge?.status.isOpen == true
            && (priorChallenge?.id != challenge?.id
                || challenge?.status.isOpen != true)
        let contextChanged = self.ownerID != ownerID
            || challengeID != challenge?.id
            || activeChallenge?.termsFingerprint != fingerprint
            || shouldRemovePriorCache
        guard contextChanged else {
            activeChallenge = challenge
            publish()
            return
        }

        generation = UUID()
        let currentGeneration = generation
        refreshTask?.cancel()
        refreshTask = nil
        needsTrailingRefresh = false
        self.ownerID = ownerID
        challengeID = challenge?.id
        activeChallenge = challenge
        liveSnapshot = nil
        cachedSnapshot = nil
        lastHealthError = nil
        lastUploadError = nil
        publish()

        // A successful same-account server transition to terminal/no-open
        // state ends the local snapshot's retention window. Account switches
        // deliberately do not delete the other account's protected cache.
        if shouldRemovePriorCache, let priorOwnerID,
            let priorChallengeID = priorChallenge?.id
        {
            try? await cache.remove(
                ownerID: priorOwnerID,
                challengeID: priorChallengeID
            )
            guard self.generation == currentGeneration else { return }
        }

        guard let ownerID, let challenge,
            challenge.stepDataPolicy.usesAutomaticHealthProgress,
            let fingerprint, !fingerprint.isEmpty
        else { return }
        do {
            let cached = try await cache.load(
                ownerID: ownerID,
                challengeID: challenge.id,
                termsFingerprint: fingerprint
            )
            guard isCurrent(
                ownerID: ownerID,
                challengeID: challenge.id,
                generation: currentGeneration
            ) else { return }
            cachedSnapshot = cached
            publish()
        } catch {
            guard generation == currentGeneration else { return }
            // A cache miss or protected-data lock falls through to the server
            // value. A later successful Health read replaces it whole.
        }
        if shouldReadHealth { await refresh() }
    }

    func updateServerChallenge(_ challenge: PersonalChallengeSummary) {
        guard challenge.id == challengeID else { return }
        activeChallenge = challenge
        publish()
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        let outcome = try await reader.requestAuthorization()
        if outcome == .requestCompleted {
            // Permission completion is the UI boundary. A Health read may
            // include seven queries, protected cache I/O, and a network
            // upload, so it must not keep the Connect action waiting.
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        return outcome
    }

    /// Coalesces any overlap into the active read plus at most one trailing
    /// full-window read. Callers awaiting this method also await that trailing
    /// read, which makes pull-to-refresh deterministic.
    func refresh() async {
        guard shouldReadHealth else {
            publish()
            return
        }
        if let refreshTask {
            needsTrailingRefresh = true
            await refreshTask.value
            return
        }
        let currentGeneration = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefreshLoop(generation: currentGeneration)
        }
        refreshTask = task
        await task.value
    }

    func progress(
        for challenge: PersonalChallengeSummary,
        now: Date = Date()
    ) -> PersonalDisplayedProgress? {
        PersonalDisplayedProgressResolver.resolve(
            challenge: challenge,
            live: challenge.id == challengeID ? liveSnapshot : nil,
            cached: challenge.id == challengeID ? cachedSnapshot : nil,
            now: now,
            stale: challenge.id == challengeID && lastHealthError != nil
        )
    }

    func progress(
        for challenge: PersonalChallengeDetail,
        now: Date = Date()
    ) -> PersonalDisplayedProgress? {
        PersonalDisplayedProgressResolver.resolve(
            challenge: challenge,
            live: challenge.id == challengeID ? liveSnapshot : nil,
            cached: challenge.id == challengeID ? cachedSnapshot : nil,
            now: now,
            stale: challenge.id == challengeID && lastHealthError != nil
        )
    }

    private var shouldReadHealth: Bool {
        guard ownerID != nil, let challenge = activeChallenge,
            challenge.status.isOpen,
            challenge.stepDataPolicy.usesAutomaticHealthProgress,
            challenge.termsFingerprint?.isEmpty == false
        else { return false }
        return Date() < challenge.terms.evidenceCutoff
    }

    private func runRefreshLoop(generation: UUID) async {
        guard self.generation == generation else { return }
        isRefreshing = true
        defer {
            if self.generation == generation {
                isRefreshing = false
                refreshTask = nil
            }
        }
        repeat {
            needsTrailingRefresh = false
            await performRefresh(generation: generation)
        } while needsTrailingRefresh
            && self.generation == generation
            && !Task.isCancelled
    }

    private func performRefresh(generation: UUID) async {
        guard let ownerID, let challenge = activeChallenge,
            let fingerprint = challenge.termsFingerprint,
            isCurrent(
                ownerID: ownerID,
                challengeID: challenge.id,
                generation: generation
            )
        else { return }
        do {
            let snapshot = try await reader.readSnapshot(
                challengeID: challenge.id,
                terms: challenge.terms,
                termsFingerprint: fingerprint,
                observedAt: Date()
            )
            guard snapshot.matches(
                challengeID: challenge.id,
                termsFingerprint: fingerprint
            ), isCurrent(
                ownerID: ownerID,
                challengeID: challenge.id,
                generation: generation
            ), !Task.isCancelled else { return }

            // A valid zero or lower total is an authoritative replacement.
            liveSnapshot = snapshot
            lastHealthError = nil
            publish()

            do {
                try await cache.save(snapshot, ownerID: ownerID)
                guard isCurrent(
                    ownerID: ownerID,
                    challengeID: challenge.id,
                    generation: generation
                ) else { return }
                cachedSnapshot = snapshot
            } catch {
                // The just-read value remains visible for this process.
            }

            do {
                try await uploader.upload(
                    snapshot,
                    expectedUserID: ownerID
                )
                guard isCurrent(
                    ownerID: ownerID,
                    challengeID: challenge.id,
                    generation: generation
                ) else { return }
                lastUploadError = nil
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(
                    ownerID: ownerID,
                    challengeID: challenge.id,
                    generation: generation
                ) else { return }
                lastUploadError = error.localizedDescription
                // Upload state never participates in display precedence.
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(
                ownerID: ownerID,
                challengeID: challenge.id,
                generation: generation
            ) else { return }
            lastHealthError = error.localizedDescription
            // Preserve the last coherent snapshot and mark it stale.
            publish()
            if let retained = liveSnapshot ?? cachedSnapshot {
                do {
                    try await uploader.upload(
                        retained,
                        expectedUserID: ownerID
                    )
                    guard isCurrent(
                        ownerID: ownerID,
                        challengeID: challenge.id,
                        generation: generation
                    ) else { return }
                    lastUploadError = nil
                } catch is CancellationError {
                    return
                } catch {
                    guard isCurrent(
                        ownerID: ownerID,
                        challengeID: challenge.id,
                        generation: generation
                    ) else { return }
                    lastUploadError = error.localizedDescription
                }
            }
        }
    }

    private func publish() {
        guard let activeChallenge else {
            displayedProgress = nil
            return
        }
        displayedProgress = PersonalDisplayedProgressResolver.resolve(
            challenge: activeChallenge,
            live: liveSnapshot,
            cached: cachedSnapshot,
            stale: lastHealthError != nil
        )
    }

    private func isCurrent(
        ownerID: UUID,
        challengeID: UUID,
        generation: UUID
    ) -> Bool {
        self.ownerID == ownerID
            && self.challengeID == challengeID
            && self.generation == generation
    }
}
