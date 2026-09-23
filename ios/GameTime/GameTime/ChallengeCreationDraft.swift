import Foundation
import Observation
import GameTimeCore

/// One owner for the presented flow. Steps never own network work or agreement consent.
@MainActor @Observable final class ChallengeCreationDraft {
    enum Step: Int, CaseIterable { case type, activity, review }
    enum InputSection { case activity, dates, amount }
    let id = UUID()
    let directEntry: Bool
    /// The policies the server lets this account create (challenge_availability_v1).
    /// nil means no per-policy restriction applies.
    let allowed: Set<String>?
    let allowsTypeChange: Bool
    var step: Step
    var mode: ChallengeV1Policy.Mode { didSet { if mode != oldValue { target = ""; competition = .goal; keepAllowedMetric(); changed() } } }
    var metric: ChallengeV1Policy.Metric { didSet { if metric != oldValue { target = ""; distance = ""; changed() } } }
    var competition: ChallengeV1Policy.Competition { didSet { if competition != oldValue { keepAllowedMetric(); changed() } } }
    var start: Date { didSet { if start != oldValue { changed() } } }
    var days = "7" { didSet { if days != oldValue { changed() } } }
    var dollars = "20" { didSet { if dollars != oldValue { changed() } } }
    var zone: String { didSet {
        if zone != oldValue {
            var previous = Calendar(identifier: .gregorian); previous.timeZone = TimeZone(identifier: oldValue) ?? .current
            let day = previous.dateComponents([.year, .month, .day], from: start)
            if let date = calendar.date(from: day) { start = date }
            changed()
        }
    } }
    var distance = "" { didSet { if distance != oldValue { changed() } } }
    var target = "" { didSet { if target != oldValue { changed() } } }
    var consent = false
    private(set) var preview: ChallengeV1.Agreement?
    private(set) var reading = false
    private(set) var initialized = false
    private(set) var receipt: ChallengeV1Receipt?
    private(set) var savedPolicy: ChallengeV1Policy?
    var error: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var alive = true
    @ObservationIgnored private var initializing = false
    @ObservationIgnored private var planningDate: Date
    @ObservationIgnored private var health: ChallengeHealthFlowStore?
    @ObservationIgnored private var usesHealth = false

    /// `personalStepsOnly` is the private trial's pair list, for callers and
    /// tests from before the server reported one.
    init(initialPolicy: ChallengeV1Policy? = nil, allowed: Set<String>? = nil, personalStepsOnly: Bool = false,
         now: Date = Date(), zone: String = TimeZone.current.identifier) {
        let allowed = personalStepsOnly ? ChallengeV1Availability.privateTrialPolicies : allowed
        self.allowed = allowed
        let types = Self.types(allowed: allowed)
        allowsTypeChange = initialPolicy == nil && types.count > 1
        planningDate = now
        directEntry = true
        step = .activity
        let first = types.first ?? (.friend, .goal)
        mode = initialPolicy?.mode ?? first.0
        competition = initialPolicy?.competition ?? first.1
        metric = initialPolicy?.metric ?? Self.metrics(mode: first.0, competition: first.1, allowed: allowed).first ?? .steps
        self.zone = zone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone) ?? .current
        start = calendar.date(byAdding: .day, value: 2, to: now)!
    }
    /// The kinds of challenge this account may create, friend goals first.
    static func types(allowed: Set<String>?) -> [(ChallengeV1Policy.Mode, ChallengeV1Policy.Competition)] {
        [(.friend, .goal), (.personal, .goal), (.friend, .leaderboard)].filter { type in
            !metrics(mode: type.0, competition: type.1, allowed: allowed).isEmpty
        }
    }
    static func metrics(mode: ChallengeV1Policy.Mode, competition: ChallengeV1Policy.Competition,
                        allowed: Set<String>?) -> [ChallengeV1Policy.Metric] {
        ChallengeV1Policy.Metric.allCases.filter { metric in
            guard let allowed else { return true }
            let prefix = "\(mode.rawValue)_\(metric.rawValue)_\(mode == .personal ? "goal" : competition.rawValue)_"
            return allowed.contains { $0.hasPrefix(prefix) }
        }
    }
    var metrics: [ChallengeV1Policy.Metric] { Self.metrics(mode: mode, competition: competition, allowed: allowed) }
    func permits(_ mode: ChallengeV1Policy.Mode, _ competition: ChallengeV1Policy.Competition) -> Bool {
        !Self.metrics(mode: mode, competition: competition, allowed: allowed).isEmpty
    }
    private func keepAllowedMetric() {
        if !metrics.contains(metric), let first = metrics.first { metric = first }
    }
    var policy: ChallengeV1Policy {
        let version = usesHealth && mode == .friend && competition == .leaderboard ? "v2" : "v1"
        return ChallengeV1Policy(rawValue: "\(mode.rawValue)_\(metric.rawValue)_\(mode == .personal ? "goal" : competition.rawValue)_\(version)")!
    }
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        return calendar
    }
    var allowedDates: ClosedRange<Date> {
        let today = calendar.startOfDay(for: planningDate)
        return calendar.date(byAdding: .day, value: 2, to: today)!...calendar.date(byAdding: .day, value: 30, to: today)!
    }
    var startDate: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
    var config: ChallengeJSON {
        var fields: [String: ChallengeJSON] = ["start_date": .string(startDate), "days": .integer(Int(days) ?? 0),
            "timezone": .string(zone), "amount_cents": .integer((wholeDollars ?? 0) * 100)]
        if metric == .timed, let value = ChallengeV1Policy.Metric.distance.parse(distance) { fields["distance_mm"] = .integer(value) }
        return .object(fields)
    }
    var wholeDollars: Int? { Self.integer(dollars, in: 1...500) }
    var duration: Int? { Self.integer(days, in: 1...30) }
    static func integer(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text), range.contains(value) else { return nil }
        return value
    }
    var fingerprint: String { "\(policy.id)|\(startDate)|\(days)|\(dollars)|\(zone)|\(distance)|\(target)" }
    var source: ChallengeHealthRealSourcePolicy? { ChallengeHealthBindingMapper.selectedSource(metric) }
    var sourceFields: [String: ChallengeJSON] { usesHealth ? source.map { ["source_policy_version": .string($0.identifier)] } ?? [:] : [:] }
    var unavailable: Bool { usesHealth && ((!policy.hasTarget && !policy.usesReceivedScores) || source == nil) }
    var progress: Int { step.rawValue + (directEntry ? 0 : 1) }
    var stepCount: Int { directEntry ? 2 : 3 }
    var firstStep: Step { directEntry ? .activity : .type }
    var window: ChallengeV1.Window? {
        if let preview { return decodeWindow(preview.terms?["config"]) }
        guard let days = duration, let dollars = wholeDollars else { return nil }
        let first = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: days, to: first) else { return nil }
        return .init(startDate: startDate, days: days, timezone: zone, amountCents: dollars * 100,
            distanceMm: metric == .timed ? ChallengeV1Policy.Metric.distance.parse(distance) : nil,
            startsAt: .init(date: first), endsAt: .init(date: end), syncBy: .init(date: end.addingTimeInterval(86400)),
            correctionsBy: .init(date: end.addingTimeInterval(172800)), noticeDue: .init(date: end.addingTimeInterval(259200)))
    }
    func planningBinding(actor: UUID?) -> ChallengeHealthBinding? {
        guard let actor, let source else { return nil }
        return try? ChallengeHealthBindingMapper.planningDraft(actor: actor, id: id, policy: policy, config: config, source: source.identifier, draft: fingerprint)
    }
    func healthBinding(actor: UUID?) -> ChallengeHealthBinding? {
        guard let actor, let preview, let window = decodeWindow(preview.terms?["config"]), let source else { return nil }
        return try? ChallengeHealthBindingMapper.binding(actor: actor, id: id, version: 1, digest: preview.digest, policy: policy, window: window, source: source.identifier)
    }
    func initialize(store: ChallengeV1Store, health: ChallengeHealthFlowStore?) async {
        guard !initialized, !initializing else { return }
        initializing = true; self.health = health; usesHealth = health != nil
        let ticket = generation; let actor = store.actor
        let now = await health?.planningDate() ?? store.access?.serverTime?.date
        guard alive, actor == store.actor else { return }
        if let now { planningDate = now }
        if ticket == generation, let now { start = calendar.date(byAdding: .day, value: 2, to: now)! }
        initialized = true
    }
    func changed() {
        generation = UUID(); preview = nil; consent = false; error = nil; reading = false
        health?.invalidateDraft(id)
    }
    func close() { alive = false; generation = UUID(); health?.cancel(id) }
    func back() { if reading { changed() }; consent = false; error = nil; step = Step(rawValue: max(firstStep.rawValue, step.rawValue - 1))! }
    func validate(_ section: InputSection) -> Bool {
        error = nil
        if section == .activity {
            if metric == .timed && ChallengeV1Policy.Metric.distance.parse(distance) == nil { error = ChallengeV1Policy.Metric.distance.inputHelp }
            else if mode == .personal && metric.parse(target) == nil { error = target.isEmpty ? "Enter your goal to continue." : metric.inputHelp }
        } else if section == .dates {
            if duration == nil { error = "Choose 1 to 30 full days to continue." }
            else if TimeZone(identifier: zone) == nil { error = "Choose a time zone to continue." }
            else if !allowedDates.contains(calendar.startOfDay(for: start)) { error = "Choose a start date 2 to 30 days from today." }
        } else if section == .amount, wholeDollars == nil { error = "Enter a whole-dollar amount from $1 to $500." }
        return error == nil
    }
    var needsReview: Bool { mode == .personal && preview == nil }
    func review(store: ChallengeV1Store) async {
        guard !reading, receipt == nil, store.pending == nil,
              validate(.activity), validate(.dates), validate(.amount) else { return }
        if mode == .personal, !(await readPreview(store: store)) { return }
        step = .review
    }
    func advance(store: ChallengeV1Store) async {
        guard !reading, receipt == nil, store.pending == nil else { return }
        if step == .type { step = .activity }
        else { await review(store: store) }
    }
    func readPreview(store: ChallengeV1Store) async -> Bool {
        guard let actor = store.actor, let value = metric.parse(target) else { error = "Enter your goal and sign in again to review it."; return false }
        let ticket = generation; let before = fingerprint
        reading = true; error = nil
        defer { if ticket == generation { reading = false } }
        do {
            var fields: [String: ChallengeJSON] = ["p_policy": .string(policy.id), "p_config": config, "p_target": .integer(value)]
            if usesHealth, let source { fields["p_source_policy_version"] = .string(source.identifier) }
            let result = try await store.client.read("challenge_personal_preview_v1", fields: fields, actor: actor, as: ChallengeV1.Agreement.self)
            guard alive, actor == store.actor, ticket == generation, fingerprint == before else { return false }
            guard decodeWindow(result.terms?["config"]) != nil else { throw ChallengeV1Error.invalidResponse }
            preview = result; consent = false
            return true
        } catch {
            guard alive, actor == store.actor, ticket == generation, fingerprint == before else { return false }
            let failure = error as? ChallengeV1Error ?? .unavailable
            self.error = failure == .unavailable ? "We couldn’t load your agreement. Check your connection, then tap Review to try again." : failure.localizedDescription
            return false
        }
    }
    func submit(store: ChallengeV1Store) async {
        guard alive, !reading, !store.busy, receipt == nil, let actor = store.actor else { return }
        let ticket = generation
        let accepted: ChallengeV1Receipt?
        var recordedPolicy = policy
        if let pending = store.pending {
            guard pending.actorId == actor else { return }
            let isCreation = ["personal_commit", "create"].contains(pending.payload["op"]?.string ?? "")
            recordedPolicy = pending.payload["policy"]?.string.flatMap(ChallengeV1Policy.init(rawValue:)) ?? policy
            await store.retry()
            guard isCreation else { return }
            accepted = store.pending == nil ? store.lastReceipt : nil
        } else {
            guard !unavailable, store.access?.ageConfirmed == true,
                  validate(.activity), validate(.dates), validate(.amount) else { return }
            var fields = sourceFields.merging(["policy": .string(policy.id), "config": config], uniquingKeysWith: { _, value in value })
            if mode == .personal {
                guard consent, let preview, let value = metric.parse(target),
                      !usesHealth || healthBinding(actor: actor).map({ health?.canConsent($0) == true }) == true else { return }
                fields.merge(["target": .integer(value), "digest": .string(preview.digest), "consent": .bool(true)], uniquingKeysWith: { _, value in value })
            }
            accepted = await store.submit(op: mode == .personal ? "personal_commit" : "create", fields: fields)
        }
        guard alive, actor == store.actor, ticket == generation, let accepted, accepted.id != nil,
              ["scheduled", "active", "lobby_open"].contains(accepted.status ?? "") else { return }
        receipt = accepted; savedPolicy = recordedPolicy; consent = false
        if let id = accepted.id { await store.loadDetail(id) }
    }
}
