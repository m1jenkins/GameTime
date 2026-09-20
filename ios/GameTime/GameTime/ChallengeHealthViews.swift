import SwiftUI
import GameTimeCore

enum ChallengeHealthCopy {
    static func source(_ identifier: String) -> String {
        switch identifier {
        case "apple_watch_steps_v1": "We count eligible steps recorded by Apple Watch in Apple Health. Entries marked as manual and records from unsupported apps or devices don’t count."
        case "apple_watch_exercise_v1": "This agreement’s activity source isn’t available. We can’t check how its Exercise credit was earned. Missing activity won’t count against you."
        case "apple_watch_exercise_credit_v2": "Activity minutes use Apple Exercise credit recorded by Apple Watch. They don’t represent every minute you move. We exclude entries marked as manual and identifiable unsupported apps or devices. Apple Health doesn’t tell us which activity caused every credit, so indirectly derived credit may count."
        case "apple_workout_outdoor_distance_v1": "We count eligible outdoor runs recorded by Apple’s Workout app on Apple Watch. A whole run must fit inside your challenge dates; a run crossing either boundary doesn’t count."
        case "apple_workout_outdoor_timed_v1": "We use whole outdoor runs recorded by Apple’s Workout app on Apple Watch. Time from start to finish includes pauses. You must finish strictly under your goal time."
        default: "This activity source isn’t available. Refresh your challenge to check its rules."
        }
    }
    static func title(_ state: ChallengeHealthReadiness) -> String {
        switch state {
        case .unsupported: "Activity not available yet"
        case .notConnected: "Connect Apple Health"
        case .checking: "Checking your activity"
        case .ready: "Activity found"
        case .noEligibleDataYet: "No matching activity yet"
        case .temporarilyUnavailable: "Activity temporarily unavailable"
        case .staleOrIncomplete: "Activity needs another check"
        }
    }
    static func explanation(_ state: ChallengeHealthReadiness, timed: Bool, readiness: Bool = true) -> String {
        switch state {
        case .unsupported: "We can’t use this activity with these rules yet. Choose another activity or check again later."
        case .notConnected: "Connect Apple Health when you’re ready to check your activity. You can keep browsing without connecting."
        case .checking: "We’re checking the activity on this phone. You can leave and refresh when you return."
        case .ready: "We found matching activity. This doesn’t mean your entire activity history is available."
        case .noEligibleDataYet: !readiness ? "We haven’t found matching activity for this challenge. Let your Watch sync, then try Refresh. Missing activity doesn’t count against you." : timed ? "We couldn’t find a comparable outdoor run in the last 90 days. Check your Apple Health settings and refresh after your Watch has synced." : "We couldn’t find matching activity in the last 30 days. Check your Apple Health settings and refresh after your Watch has synced."
        case .temporarilyUnavailable: "Check your connection and try Refresh. Missing activity doesn’t count against you."
        case .staleOrIncomplete: "Some activity changed or couldn’t be read. Try Refresh after your Watch has synced. We won’t treat missing activity as zero."
        }
    }
}

struct ChallengeHealthStatusView: View {
    @Bindable var flow: ChallengeHealthFlowStore
    let binding: ChallengeHealthBinding
    var readiness = false
    private var state: ChallengeHealthFlowStore.State { flow.state(for: binding) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ChallengeHealthCopy.title(state.readiness)).font(.headline).accessibilityIdentifier("beta.health.state")
            Text(ChallengeHealthCopy.explanation(state.readiness, timed: binding.metric == .timedRunElapsedSeconds, readiness: readiness)).font(.subheadline)
            if readiness {
                Button(state.readiness == .notConnected ? "Connect Apple Health" : "Refresh activity check") {
                    Task { await flow.checkReadiness(binding, connect: state.readiness == .notConnected) }
                }.disabled(state.readiness == .checking || state.readiness == .unsupported).accessibilityIdentifier("beta.health.connect")
                if state.readiness == .ready && !flow.canConsent(binding) {
                    Text("Finish sending this activity check before you agree. Try Refresh.").font(.subheadline)
                }
            } else {
                if state.readiness == .notConnected {
                    Button("Connect Apple Health") {
                        Task {
                            await flow.checkReadiness(binding, connect: true)
                            await flow.refresh(binding.challengeID)
                        }
                    }.accessibilityIdentifier("beta.health.connect")
                }
                if let value = state.localValue, let metric = ChallengeV1Policy.Metric.allCases.first(where: { ChallengeHealthBindingMapper.metric($0) == binding.metric }) {
                    Text("On this phone: \(metric.display(Int(value)))").font(.subheadline).accessibilityIdentifier("beta.health.local-value")
                }
                if let observed = state.observedAt { Text("Checked on this phone \(observed, format: .dateTime.month().day().hour().minute())").font(.caption) }
                if let updated = state.lastServerUpdate { Text("Last server update \(updated, format: .dateTime.month().day().hour().minute())").font(.caption) }
            }
            if state.pendingDelivery { Text("Waiting to send this update").font(.subheadline).accessibilityIdentifier("beta.health.pending") }
            if let message = state.message { Text(message).font(.subheadline) }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
    }
}

struct ChallengeHealthSuggestionView: View {
    @Bindable var flow: ChallengeHealthFlowStore
    let binding: ChallengeHealthBinding
    let policy: ChallengeV1Policy
    let days: Int
    let select: (Int) -> Void
    var body: some View {
        if policy.hasTarget && policy.mode != .community {
            VStack(alignment: .leading, spacing: 10) {
                Button("Find a suggestion on this phone") { Task { await flow.suggest(binding, policy: policy, days: days) } }
                    .disabled(flow.state(for: binding).readiness == .unsupported || flow.state(for: binding).readiness == .checking)
                if let value = flow.suggestions[binding.challengeID] {
                    Text("Suggestion: \(policy.metric.display(value)). Your past activity stays on this phone. You choose whether to use this goal.")
                    Button("Use this suggestion") { select(value) }
                }
            }.font(.subheadline)
        }
    }
}

extension ChallengeV1Policy.Metric {
    func inputValue(_ value: Int) -> String {
        switch self {
        case .steps: String(value)
        case .exercise, .timed: "\(value / 60):\(String(format: "%02d", value % 60))"
        case .distance: NSDecimalNumber(decimal: Decimal(value) / 1_000_000).stringValue
        }
    }
}
