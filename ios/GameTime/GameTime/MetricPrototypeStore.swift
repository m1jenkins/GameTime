import Foundation
import Observation

/// A private fixture notebook. It records consent and replacement observations;
/// only the separate TypeScript fixture evaluator can evaluate metric results.
/// Synchronous MainActor transactions avoid late responses and actor-switch races.
@MainActor @Observable
final class MetricPrototypeStore {
    private(set) var actorID: UUID?
    private(set) var agreements: [MetricPrototypeAgreement] = []
    private(set) var errorMessage: String?
    let enabled: Bool
    private let directory: URL
    private let now: () -> Date
    private var deletedActors: Set<UUID> = []

    private enum Command: Codable, Equatable {
        case create(MetricPrototypeDraft, consent: Bool)
        case proof(UUID, MetricPrototypeProofDraft)
        case exit(UUID)
    }
    private struct Receipt: Codable {
        let requestID: UUID
        let command: Command
        let agreementID: UUID
    }
    private struct Notebook: Codable {
        let version: String
        let actorID: UUID
        var agreements: [MetricPrototypeAgreement]
        var receipts: [Receipt]
    }

    init(enabled: Bool = false, directory: URL, now: @escaping () -> Date = Date.init) {
        #if DEBUG || STAGING
        self.enabled = enabled
        #else
        self.enabled = false
        #endif
        self.directory = directory
        self.now = now
    }

    static func applicationSupport(enabled: Bool = false) throws -> MetricPrototypeStore {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw MetricPrototypeError.storage }
        return MetricPrototypeStore(enabled: enabled,
            directory: root.appendingPathComponent("GameTime/MetricPractice", isDirectory: true))
    }

    func setActor(_ actorID: UUID?) {
        agreements = []; errorMessage = nil
        self.actorID = actorID
        do { try refresh() } catch { errorMessage = error.localizedDescription }
    }

    func refresh() throws {
        agreements = []; errorMessage = nil
        guard let actorID else { return }
        do { agreements = try load(actorID).agreements }
        catch { errorMessage = MetricPrototypeError.storage.localizedDescription; throw MetricPrototypeError.storage }
    }

    @discardableResult
    func create(draft: MetricPrototypeDraft, consent: Bool, requestID: UUID) throws -> UUID {
        try transact(.create(draft, consent: consent), requestID: requestID)
    }
    func appendProof(agreementID: UUID, draft: MetricPrototypeProofDraft, requestID: UUID) throws {
        _ = try transact(.proof(agreementID, draft), requestID: requestID)
    }
    func exit(agreementID: UUID, requestID: UUID) throws {
        _ = try transact(.exit(agreementID), requestID: requestID)
    }

    /// Called by the trusted account-cleanup coordinator, including after signout
    /// or with the feature off. No file contents are read or returned here.
    /// The fence also rejects all later writes from this store instance.
    func deleteLocalAccount(_ actorID: UUID) throws {
        deletedActors.insert(actorID)
        if self.actorID == actorID { agreements = []; self.actorID = nil; errorMessage = nil }
        let url = file(actorID)
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch { errorMessage = MetricPrototypeError.storage.localizedDescription; throw MetricPrototypeError.storage }
    }

    private func transact(_ command: Command, requestID: UUID) throws -> UUID {
        guard let actorID, !deletedActors.contains(actorID) else { throw MetricPrototypeError.accountChanged }
        var notebook = try load(actorID)
        // Recover the exact persisted operation before any changed clock/gate.
        if let receipt = notebook.receipts.first(where: { $0.requestID == requestID }) {
            guard receipt.command == command else { throw MetricPrototypeError.requestConflict }
            agreements = notebook.agreements
            return receipt.agreementID
        }
        let instant = DuelInstant(date: now())
        let agreementID: UUID
        var usesReservedExitSpace = false
        switch command {
        case .create(let draft, let consent):
            guard enabled else { throw MetricPrototypeError.unavailable }
            guard notebook.receipts.count < 1_024 else { throw MetricPrototypeError.capacity }
            guard consent else { throw MetricPrototypeError.consentRequired }
            guard notebook.agreements.count < 50,
                notebook.agreements.filter({ $0.exitedAt == nil && instant < $0.terms.correctionsCloseAt }).count < 3
            else { throw MetricPrototypeError.capacity }
            agreementID = requestID
            let terms = try MetricPrototypeTerms(actorID: actorID, agreementID: agreementID, draft: draft, createdAt: instant)
            notebook.agreements.append(MetricPrototypeAgreement(terms: terms, consentBinding: try terms.binding,
                consentAt: instant, proofs: [], exitedAt: nil))
        case .proof(let id, let draft):
            guard enabled else { throw MetricPrototypeError.unavailable }
            guard notebook.receipts.count < 1_024 else { throw MetricPrototypeError.capacity }
            guard let index = notebook.agreements.firstIndex(where: { $0.id == id }) else { throw MetricPrototypeError.accountChanged }
            let agreement = notebook.agreements[index]
            guard agreement.exitedAt == nil, instant >= agreement.terms.draft.startsAt,
                instant < agreement.terms.correctionsCloseAt else { throw MetricPrototypeError.closed }
            guard agreement.proofs.count < 100 else { throw MetricPrototypeError.capacity }
            try draft.validate(for: agreement.terms, recordedAt: instant)
            guard agreement.proofs.last.map({ instant > $0.recordedAt }) ?? true else { throw MetricPrototypeError.invalidProof }
            let proof = MetricPrototypeProofRevision(id: requestID, revision: agreement.proofs.count + 1,
                previousRevision: agreement.proofs.last?.revision, termsBinding: agreement.consentBinding,
                recordedAt: instant, draft: draft)
            notebook.agreements[index].proofs.append(proof)
            agreementID = id
        case .exit(let id):
            guard let index = notebook.agreements.firstIndex(where: { $0.id == id }) else { throw MetricPrototypeError.accountChanged }
            // Reserve one first-exit receipt per agreement beyond the general
            // request cap. Repeated new exit keys cannot consume this reserve.
            guard notebook.receipts.count < 1_024 || notebook.agreements[index].exitedAt == nil
            else { throw MetricPrototypeError.capacity }
            usesReservedExitSpace = notebook.agreements[index].exitedAt == nil
            // Leaving remains possible after the fixture admission switch is off.
            // A backward phone-clock change cannot prevent a safe exit. This is
            // a local logical timestamp, never an authoritative scoring clock.
            if notebook.agreements[index].exitedAt == nil {
                let last = notebook.agreements[index].proofs.last?.recordedAt ?? notebook.agreements[index].consentAt
                notebook.agreements[index].exitedAt = max(instant, last)
            }
            agreementID = id
        }
        notebook.receipts.append(Receipt(requestID: requestID, command: command, agreementID: agreementID))
        try save(notebook, usesReservedExitSpace: usesReservedExitSpace)
        agreements = notebook.agreements; errorMessage = nil
        return agreementID
    }

    private func validate(_ notebook: Notebook) throws {
        guard notebook.version == "metric-prototype-notebook-v1", notebook.agreements.count <= 50,
            notebook.receipts.count <= 1_074,
            Set(notebook.agreements.map(\.id)).count == notebook.agreements.count,
            Set(notebook.receipts.map(\.requestID)).count == notebook.receipts.count
        else { throw MetricPrototypeError.storage }
        for agreement in notebook.agreements { try agreement.validate(for: notebook.actorID) }
        for receipt in notebook.receipts {
            guard let agreement = notebook.agreements.first(where: { $0.id == receipt.agreementID })
            else { throw MetricPrototypeError.storage }
            switch receipt.command {
            case .create(let draft, let consent):
                guard consent, receipt.requestID == agreement.id, draft == agreement.terms.draft
                else { throw MetricPrototypeError.storage }
            case .proof(let id, let draft):
                guard id == agreement.id, agreement.proofs.contains(where: { $0.id == receipt.requestID && $0.draft == draft })
                else { throw MetricPrototypeError.storage }
            case .exit(let id):
                guard id == agreement.id, agreement.exitedAt != nil else { throw MetricPrototypeError.storage }
            }
        }
        for agreement in notebook.agreements {
            guard notebook.receipts.contains(where: { $0.requestID == agreement.id }),
                agreement.proofs.allSatisfy({ proof in notebook.receipts.contains(where: { $0.requestID == proof.id }) })
            else { throw MetricPrototypeError.storage }
        }
    }

    private func load(_ actorID: UUID) throws -> Notebook {
        guard !deletedActors.contains(actorID) else { throw MetricPrototypeError.accountChanged }
        let url = file(actorID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Notebook(version: "metric-prototype-notebook-v1", actorID: actorID, agreements: [], receipts: [])
        }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                values.fileSize.map({ $0 <= 2_097_152 }) == true else { throw MetricPrototypeError.storage }
            let notebook = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: url))
            guard notebook.actorID == actorID else { throw MetricPrototypeError.storage }
            try validate(notebook)
            return notebook
        } catch { throw MetricPrototypeError.storage }
    }
    private func save(_ notebook: Notebook, usesReservedExitSpace: Bool) throws {
        do {
            try validate(notebook)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try excludeFromBackup(directory)
            let data = try JSONEncoder().encode(notebook)
            // Reserve 64 KiB for bounded first exits as well as their receipt
            // slots, so reaching the ordinary byte cap cannot block leaving.
            guard data.count <= (usesReservedExitSpace ? 2_097_152 : 2_031_616)
            else { throw MetricPrototypeError.capacity }
            try data.write(to: file(notebook.actorID), options: [.atomic, .completeFileProtection])
            try excludeFromBackup(file(notebook.actorID))
        } catch let error as MetricPrototypeError { throw error }
        catch { throw MetricPrototypeError.storage }
    }
    private func file(_ actorID: UUID) -> URL { directory.appendingPathComponent("\(actorID.uuidString.lowercased()).json") }
    private func excludeFromBackup(_ url: URL) throws {
        var url = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
