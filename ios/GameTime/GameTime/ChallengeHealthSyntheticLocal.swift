#if DEBUG
import Foundation
import GameTimeCore
import Supabase

/// Explicitly local-only. This dependency graph never creates a HealthKit
/// reader, permission service, or physical App Attest signer.
@MainActor final class ChallengeHealthSyntheticLocal: AppAttestedBodySigning, ChallengeHealthPermissionService {
    let origin: URL
    private let control: String
    private let session: URLSession
    private(set) var now = Date()
    var supported: Bool { true }

    init(origin: URL, control: String) throws {
        guard SupabaseWeeklyClient.isExplicitLoopback(origin), control.count >= 32 else { throw ChallengeV1Error.unavailable }
        self.origin = origin; self.control = control
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config, delegate: LocalNoRedirect(), delegateQueue: nil)
    }
    func connect(_ metric: ChallengeHealthMetric) async throws { try await updateClock() }
    func updateClock() async throws {
        let result: Clock = try await call("clock")
        guard let date = ISO8601DateFormatter().date(from: result.now) else { throw ChallengeV1Error.invalidResponse }
        now = date
    }
    func sign(ownerID: UUID, body: Data) async throws -> MetricSignedMaterial {
        struct Signed: Decodable { let key: String; let assertion: String }
        let result: Signed = try await call("sign", body: ["actor": ownerID.uuidString.lowercased(), "body": body.base64EncodedString()])
        guard let assertion = Data(base64Encoded: result.assertion) else { throw ChallengeV1Error.invalidResponse }
        return MetricSignedMaterial(keyID: result.key, assertion: assertion, environment: .development)
    }
    func invalidateRejectedKey(ownerID: UUID, keyID: String) throws { throw ChallengeV1Error.unavailable }
    func input(actor: UUID) async throws -> Input { try await call("input?actor=" + actor.uuidString.lowercased()) }
    struct Clock: Decodable { let now: String }
    struct Input: Decodable { let mode: String; let value: Int64; let now: String }
    private func call<T: Decodable>(_ path: String, body: [String: String]? = nil) async throws -> T {
        guard let url = URL(string: "p9/" + path, relativeTo: origin.appendingPathComponent("/")) else { throw ChallengeV1Error.unavailable }
        var request = URLRequest(url: url)
        request.setValue(control, forHTTPHeaderField: "x-p9-control")
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 65536 else { throw ChallengeV1Error.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func dependencies(sdk: SupabaseClient, key: String, directory: URL) throws -> ChallengeHealthFlowDependencies {
        let transport = ChallengeHealthTransportCoordinator(
            uploadStore: .init(directory: directory.appendingPathComponent("upload")),
            readinessStore: .init(directory: directory.appendingPathComponent("readiness")), binding: {
                guard let session = sdk.auth.currentSession, session.expiresAt > Date().timeIntervalSince1970 else { return nil }
                return WeeklyClientSession(actorID: session.user.id, identity: session.accessToken)
            })
        let uploads = try ChallengeHealthUploadClient(sdk: sdk, origin: origin, publishableKey: key,
            signer: self, environment: .development, coordinator: transport, enabled: true)
        let readiness = try ChallengeHealthReadinessClient(sdk: sdk, origin: origin, publishableKey: key,
            signer: self, environment: .development, coordinator: transport, enabled: true)
        return ChallengeHealthFlowDependencies(coordinator: transport, uploads: uploads, readiness: readiness,
            cache: .init(directory: directory.appendingPathComponent("comparison")), permission: self,
            reader: { [self] _, _ in Reader(source: self) }, adapter: ChallengeHealthBindingMapper.adapter,
            now: { [self] in now }, updateClock: { [self] in try await updateClock() }, actorSession: {
                guard let session = sdk.auth.currentSession, session.expiresAt > Date().timeIntervalSince1970,
                      let identity = ChallengeHealthTransportCoordinator.sessionID(session.accessToken) else { return nil }
                return WeeklyClientSession(actorID: session.user.id, identity: identity.uuidString)
            })
    }
    @MainActor private final class Reader: ChallengeHealthStore {
        let source: ChallengeHealthSyntheticLocal
        init(source: ChallengeHealthSyntheticLocal) { self.source = source }
        func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
            do {
                let input = try await source.input(actor: request.binding.actorID)
                try Task.checkCancellation()
                guard let observed = ISO8601DateFormatter().date(from: input.now) else { return .unavailable(.queryFailed) }
                let activity = request.purpose == .challengeActivity
                if activity && input.mode == "unresolved" { return .unavailable(.queryFailed) }
                let id = request.binding.challengeID // Stable local-only synthetic record identity across relaunch.
                let start = request.queryWindow.interval.start.addingTimeInterval(60)
                let value = activity ? input.value : (request.binding.metric == .timedRunElapsedSeconds ? 1000 : 25000)
                let duration = request.binding.metric == .timedRunElapsedSeconds ? Double(value) : 600
                let end = min(start.addingTimeInterval(duration), min(request.queryWindow.interval.end, observed))
                let deleted: Set<UUID> = activity && input.mode == "deleted" ? [id] : []
                let empty = activity && ["empty", "deleted"].contains(input.mode)
                let metric: WeeklySourceMetric = request.binding.metric == .steps ? .steps : request.binding.metric == .exerciseSeconds ? .appleExerciseMinutes : .runningDistanceMillimeters
                let record = WeeklySourceRecord(id: id, metric: metric, start: start, end: end,
                    value: request.binding.metric == .timedRunElapsedSeconds ? Double(request.binding.selectedDistanceMillimeters ?? 0) :
                        request.binding.metric == .exerciseSeconds ? Double(value) / 60 : Double(value), sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1",
                    wasUserEntered: false, workoutActivityType: metric == .runningDistanceMillimeters ? "running" : nil,
                    wasIndoorWorkout: metric == .runningDistanceMillimeters ? false : nil)
                return .snapshot(ChallengeHealthSnapshot(request: request, records: empty ? [] : [record], deletedRecordIDs: deleted,
                    observedAt: observed, sourceFreshness: observed,
                    evidence: deleted.isEmpty ? .boundedSnapshot : .boundedSnapshotAfterDeletion))
            } catch is CancellationError { return .unavailable(.cancelled) }
            catch { return .unavailable(.queryFailed) }
        }
    }
}
private final class LocalNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
#endif
