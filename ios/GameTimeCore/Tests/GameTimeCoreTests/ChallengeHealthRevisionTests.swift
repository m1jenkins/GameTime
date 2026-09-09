import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge Health replacement and exact retry contracts")
struct ChallengeHealthRevisionTests {
    typealias F = ChallengeHealthFixtures

    func revision(_ number: Int, previous: Int? = nil,
                  replacement: ChallengeHealthReplacement = .unresolved(.sourcePolicyUnaccepted),
                  evidence: ChallengeHealthEvidence = .unknown,
                  binding: ChallengeHealthBinding? = nil, requestID: Int? = nil,
                  observed: Int64? = nil) throws -> ChallengeHealthRevision {
        try ChallengeHealthRevision(binding: binding ?? F.binding(), deviceRequestID: F.id(requestID ?? number + 100),
            revisionID: F.id(number), previousRevisionID: previous.map(F.id), replacement: replacement,
            observedAtMicroseconds: observed ?? (F.epoch + Int64(number)) * 1_000_000,
            sourceFreshnessMicroseconds: nil, evidence: evidence)
    }

    @Test("downward, deleted, and unresolved revisions replace and link instead of adding or maxing")
    func replacementChain() throws {
        var journal = ChallengeHealthRevisionJournal(binding: try F.binding())
        let large = try revision(20, replacement: .value(ChallengeHealthValue(metric: .steps, integerValue: 500)), evidence: .boundedSnapshot)
        let lower = try revision(21, previous: 20, replacement: .value(ChallengeHealthValue(metric: .steps, integerValue: 100)), evidence: .boundedSnapshot)
        let deleted = try revision(22, previous: 21, replacement: .deleted, evidence: .explicitDeletion)
        let unknown = try revision(23, previous: 22, replacement: .unresolved(.lostVisibility), evidence: .lostVisibility)
        for item in [large, lower, deleted, unknown] {
            let stored = try journal.prepare(item)
            #expect(journal.latest?.revision.replacement == item.replacement)
            #expect(!stored.permitsRealIngestion)
        }
        #expect(journal.latest?.revision.previousRevisionID == F.id(22))
        #expect(try journal.retry(deviceRequestID: lower.deviceRequestID, binding: lower.binding)?.revision == lower)
    }

    @Test("retry retains bytes and identity despite later revisions; changed bytes with reused ID are rejected")
    func exactRetry() throws {
        var journal = ChallengeHealthRevisionJournal(binding: try F.binding())
        let original = try revision(20)
        let saved = try journal.prepare(original)
        _ = try journal.prepare(revision(21, previous: 20))
        #expect(try journal.prepare(original) == saved)
        #expect(try journal.retry(deviceRequestID: original.deviceRequestID, binding: original.binding)?.exactBytes == saved.exactBytes)
        let changed = try revision(22, previous: 21, requestID: 120)
        #expect(throws: ChallengeHealthContractError.requestIDConflict) { try journal.prepare(changed) }
        #expect(journal.latest?.revision.revisionID == F.id(21))
    }

    @Test("branches, stale timestamps, repeated revision IDs and wrong metric cannot corrupt the chain")
    func invalidRevisions() throws {
        var journal = ChallengeHealthRevisionJournal(binding: try F.binding())
        _ = try journal.prepare(revision(20))
        #expect(throws: ChallengeHealthContractError.invalidRevision) { try journal.prepare(revision(21)) }
        #expect(throws: ChallengeHealthContractError.invalidRevision) {
            try journal.prepare(revision(21, previous: 20, observed: F.epoch * 1_000_000))
        }
        _ = try journal.prepare(revision(21, previous: 20))
        #expect(throws: ChallengeHealthContractError.invalidRevision) {
            try journal.prepare(revision(20, previous: 21, requestID: 130, observed: (F.epoch + 30) * 1_000_000))
        }
        #expect(throws: ChallengeHealthContractError.invalidValue) {
            try revision(22, replacement: .value(ChallengeHealthValue(metric: .exerciseSeconds, integerValue: 60)))
        }
    }

    @Test("lost visibility, empty reads and anchors cannot serve as explicit deletion evidence")
    func noDeletionFromAbsence() throws {
        for evidence in [ChallengeHealthEvidence.lostVisibility, .boundedSnapshot, .limitedHistory, .anchoredChanges, .unknown] {
            #expect(throws: ChallengeHealthContractError.invalidDeletionEvidence) {
                try revision(20, replacement: .deleted, evidence: evidence)
            }
        }
        #expect(try revision(20, replacement: .deleted, evidence: .explicitDeletion).replacement == .deleted)
    }

    @Test("account, digest, terms version, timezone and calendar fence both prepare and retry")
    func bindingFences() throws {
        let original = try revision(20)
        var journal = ChallengeHealthRevisionJournal(binding: original.binding)
        _ = try journal.prepare(original)
        let zone = try ChallengeHealthBinding(actorID: original.binding.actorID, challengeID: original.binding.challengeID,
            agreementVersion: 1, termsDigest: original.binding.termsDigest, metric: .steps,
            challengeWindow: F.window(start: 1_000, end: 2_000, zone: "Asia/Tokyo", calendar: .iso8601))
        for other in [try F.binding(actor: 9), try F.binding(version: 2),
                      try F.binding(digest: String(repeating: "b", count: 64)), zone] {
            #expect(throws: ChallengeHealthContractError.bindingMismatch) {
                try journal.prepare(revision(21, previous: 20, binding: other))
            }
            #expect(throws: ChallengeHealthContractError.bindingMismatch) {
                try journal.retry(deviceRequestID: original.deviceRequestID, binding: other)
            }
        }
        journal.switchBinding(to: try F.binding(actor: 9))
        #expect(journal.latest == nil)
        journal.switchBinding(to: original.binding)
        #expect(try journal.retry(deviceRequestID: original.deviceRequestID, binding: original.binding) == nil)
    }

    @Test("wire rehearsal is explicitly synthetic and contains only minimum normalized facts")
    func privacyAndVersion() throws {
        var journal = ChallengeHealthRevisionJournal(binding: try F.binding())
        let pending = try journal.prepare(revision(20,
            replacement: .value(ChallengeHealthValue(metric: .steps, integerValue: 100)), evidence: .boundedSnapshot))
        let object = try #require(JSONSerialization.jsonObject(with: pending.exactBytes) as? [String: Any])
        #expect(object["contractVersion"] as? Int == 1)
        #expect(object["mode"] as? String == "synthetic_only")
        #expect(Set(object.keys) == ["contractVersion", "mode", "binding", "deviceRequestID", "revisionID", "replacement", "observedAtMicroseconds", "evidence"])
        let text = String(decoding: pending.exactBytes, as: UTF8.self)
        for forbidden in ["synthetic-device-private", "synthetic.source", "sourceBundleIdentifier", "syncIdentifier",
                          "records", "route", "baseline", "earliestAuthorizedSampleDate", "queryWindow", "complete"] {
            #expect(!text.contains(forbidden))
        }
        let record: Any = F.record(), snapshot: Any = try F.snapshot([F.record()]), request: Any = try F.request()
        #expect(!(record is any Encodable) && !(snapshot is any Encodable) && !(request is any Encodable))
    }

    @Test("frozen calendar/zone and 23/25-hour intervals retain supplied boundaries")
    func frozenWindows() throws {
        for seconds: Int64 in [23 * 3_600, 25 * 3_600] {
            let window = try F.window(end: seconds)
            #expect(window.endMicroseconds - window.startMicroseconds == seconds * 1_000_000)
            #expect(window.interval.duration == Double(seconds))
            #expect(window.timeZoneIdentifier == "America/Chicago" && window.calendar == .gregorian)
        }
        let binding = try F.binding()
        #expect(throws: ChallengeHealthContractError.invalidWindow) {
            try ChallengeHealthReadRequest(binding: binding, deviceRequestID: F.id(3), queryWindow: F.window(zone: "UTC"), purpose: .readinessHistory)
        }
        #expect(throws: ChallengeHealthContractError.invalidWindow) {
            try ChallengeHealthReadRequest(binding: binding, deviceRequestID: F.id(3), queryWindow: F.window(end: 1_001), purpose: .readinessHistory)
        }
        #expect(throws: ChallengeHealthContractError.invalidWindow) { try F.window(start: 10, end: 10) }
        #expect(throws: ChallengeHealthContractError.invalidWindow) { try F.window(zone: "invalid-zone") }
        #expect(throws: ChallengeHealthContractError.invalidAgreement) { try F.binding(digest: "raw-private-data") }
        #expect(throws: ChallengeHealthContractError.invalidValue) { try ChallengeHealthValue(metric: .steps, integerValue: -1) }
        #expect(throws: ChallengeHealthContractError.invalidValue) { try ChallengeHealthValue(metric: .timedRunElapsedSeconds, integerValue: 0) }
    }
}
