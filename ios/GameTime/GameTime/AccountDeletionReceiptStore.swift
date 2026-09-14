import Foundation

enum AccountDeletionRightsOperation: String, Codable, Equatable, Sendable {
    case review
    case appeal
}

/// Saved before the restricted post-Auth request is sent. Reusing its ID and
/// payload makes a lost response an exact retry, never a second review/appeal.
struct AccountDeletionRightsRequest: Codable, Equatable, Sendable {
    let id: UUID
    let operation: AccountDeletionRightsOperation
    let challengeID: UUID?
    let noticeRevision: Int?
    let reason: String?
}

/// The opaque receipt is deliberately outside ordinary account cleanup. It is
/// the only local material needed to recover the account-closure outcome after
/// Auth has ended; it contains no Apple or payment-provider credential.
struct AccountDeletionReceipt: Codable, Equatable, Sendable {
    let ownerID: UUID
    let requestID: UUID
    let secret: String
    var pendingRightsRequest: AccountDeletionRightsRequest?

    init(
        ownerID: UUID,
        requestID: UUID = UUID(),
        secret: String,
        pendingRightsRequest: AccountDeletionRightsRequest? = nil
    ) {
        self.ownerID = ownerID
        self.requestID = requestID
        self.secret = secret
        self.pendingRightsRequest = pendingRightsRequest
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID, requestID, secret, pendingRightsRequest
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        requestID = try values.decode(UUID.self, forKey: .requestID)
        secret = try values.decode(String.self, forKey: .secret)
        pendingRightsRequest = try values.decodeIfPresent(
            AccountDeletionRightsRequest.self,
            forKey: .pendingRightsRequest
        )
    }
}

@MainActor
protocol AccountDeletionReceiptStoring: AnyObject {
    func loadLatest() throws -> AccountDeletionReceipt?
    func load(for ownerID: UUID) throws -> AccountDeletionReceipt?
    func save(_ receipt: AccountDeletionReceipt) throws
    func remove(for ownerID: UUID) throws
}

@MainActor
final class FileAccountDeletionReceiptStore: AccountDeletionReceiptStoring {
    private struct Journal: Codable {
        var receipts: [UUID: AccountDeletionReceipt]
        var latestOwnerID: UUID?
    }

    private let file: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) {
        file = directory.appendingPathComponent("account-deletion-receipt.json")
    }

    static func applicationSupport() throws -> FileAccountDeletionReceiptStore {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AccountDeletionError.unavailable
        }
        return FileAccountDeletionReceiptStore(
            directory: root.appendingPathComponent("GameTime/AccountDeletion")
        )
    }

    func loadLatest() throws -> AccountDeletionReceipt? {
        let journal = try loadJournal()
        guard let ownerID = journal?.latestOwnerID else { return nil }
        return journal?.receipts[ownerID]
    }

    func load(for ownerID: UUID) throws -> AccountDeletionReceipt? {
        try loadJournal()?.receipts[ownerID]
    }

    private func loadJournal() throws -> Journal? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard data.count <= 8 * 1024 else { throw AccountDeletionError.invalidResponse }
        // The first local build wrote one receipt. Read that safely once, then
        // preserve it alongside a later account's receipt rather than making a
        // shared-device account switch destroy recovery for the first person.
        let journal: Journal
        if let decoded = try? decoder.decode(Journal.self, from: data) {
            journal = decoded
        } else if let receipt = try? decoder.decode(AccountDeletionReceipt.self, from: data) {
            journal = Journal(
                receipts: [receipt.ownerID: receipt],
                latestOwnerID: receipt.ownerID
            )
        } else {
            throw AccountDeletionError.invalidResponse
        }
        guard journal.receipts.values.allSatisfy(valid) else {
            throw AccountDeletionError.invalidResponse
        }
        return journal
    }

    func save(_ receipt: AccountDeletionReceipt) throws {
        guard valid(receipt) else { throw AccountDeletionError.invalidResponse }
        var journal = try loadJournal()
            ?? Journal(receipts: [:], latestOwnerID: nil)
        journal.receipts[receipt.ownerID] = receipt
        journal.latestOwnerID = receipt.ownerID
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(journal).write(
            to: file,
            options: [.atomic, .completeFileProtection]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = file.deletingLastPathComponent()
        try directory.setResourceValues(values)
    }

    func remove(for ownerID: UUID) throws {
        var journal = try loadJournal()
            ?? Journal(receipts: [:], latestOwnerID: nil)
        journal.receipts.removeValue(forKey: ownerID)
        if journal.latestOwnerID == ownerID {
            journal.latestOwnerID = journal.receipts.keys.sorted {
                $0.uuidString < $1.uuidString
            }.first
        }
        if journal.receipts.isEmpty {
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            try FileManager.default.removeItem(at: file)
            return
        }
        try encoder.encode(journal).write(
            to: file,
            options: [.atomic, .completeFileProtection]
        )
    }

    private func valid(_ receipt: AccountDeletionReceipt) -> Bool {
        receipt.secret.count >= 32
            && receipt.secret.range(
                of: "^[A-Za-z0-9_-]+$",
                options: .regularExpression
            ) != nil
    }
}

@MainActor
final class EphemeralAccountDeletionReceiptStore: AccountDeletionReceiptStoring {
    private var receipts: [UUID: AccountDeletionReceipt] = [:]
    private var latestOwnerID: UUID?

    func loadLatest() throws -> AccountDeletionReceipt? {
        latestOwnerID.flatMap { receipts[$0] }
    }
    func load(for ownerID: UUID) throws -> AccountDeletionReceipt? {
        receipts[ownerID]
    }
    func save(_ receipt: AccountDeletionReceipt) throws {
        receipts[receipt.ownerID] = receipt
        latestOwnerID = receipt.ownerID
    }
    func remove(for ownerID: UUID) throws {
        receipts.removeValue(forKey: ownerID)
        if latestOwnerID == ownerID { latestOwnerID = receipts.keys.first }
    }
}
