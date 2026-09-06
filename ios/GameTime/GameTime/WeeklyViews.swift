#if DEBUG || STAGING
import SwiftUI

struct WeeklyHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var creation: WeeklyCreationSheet?
    private var store: WeeklyStore { model.weekly }
    var body: some View {
        List {
            WeeklyDisclosure()
            WeeklyRecoverySection(store: store)
            Section {
                Button("Start a friend week") { creation = WeeklyCreationSheet() }
                    .disabled(!store.canEnter).accessibilityIdentifier("weekly.create")
                Text("Choose a weekly step target together. Rest days are welcome; there’s no daily streak to keep.")
            }
            Section("Your weeks") {
                if store.isLoading { ProgressView("Loading your weeks…") }
                if store.challenges.isEmpty && !store.isLoading { Text("No saved weeks to show. Refresh or review a new week to get started.") }
                ForEach(store.challenges) { row in
                    NavigationLink { WeeklyDetailView(challengeID: row.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.mode == "community" ? "Community week" : "Friend week").font(.headline)
                            Text("Your target: \(row.own.targetSteps.formatted()) steps")
                            Text(row.result?.qualification.title ?? "\(row.acceptedCount) of \(row.participantCount) accepted")
                            Text(row.terms.fields.days[0].date).font(.caption)
                        }
                    }.accessibilityIdentifier("weekly.row.\(row.id.uuidString.lowercased())")
                }
            }
            WeeklyFollowingSections(store: store)
            Section("Community") {
                Text("Join on your own or with friends. Everyone works toward the same individual step target.")
                if store.cohorts.isEmpty { Text("No community week is open right now. Refresh to check again.") }
                ForEach(store.cohorts) { cohort in
                    NavigationLink { WeeklyCohortView(cohortID: cohort.id) } label: {
                        VStack(alignment: .leading) {
                            Text("\((cohort.terms.fields.commonTargetSteps ?? 0).formatted()) steps this week")
                            Text("\(cohort.participantCount) joined · \(cohort.capacity) places").font(.caption)
                        }
                    }.accessibilityIdentifier("weekly.cohort.\(cohort.id.uuidString.lowercased())")
                }
            }
            if let prototypes = model.metricPrototypes, model.configuration.weeklyRuntimeEnabled {
                Section("Local prototypes") {
                    NavigationLink("Try a fictional distance agreement") { MetricPrototypeView(store: prototypes) }
                    Text("A separate private practice record on this phone. No health source or result evaluation is connected.")
                }
            }
            if let preferences = store.preferences {
                Section("Your choices") {
                    Text(preferences.paused ? "New weekly entries are paused." : "New weekly entries are allowed.")
                    Button(preferences.paused ? "Allow new weekly entries" : "Pause new weekly entries") {
                        Task { await store.submit(.pause(!preferences.paused)) }
                    }.disabled(!store.canStartRequest).accessibilityIdentifier("weekly.pause")
                    Text("Pausing does not cancel a week. Your history, review, support and exit choices stay available.")
                    Button(preferences.pilotConsent ? "Stop optional study records" : "Allow optional study records") {
                        Task { await store.submit(.pilotConsent(!preferences.pilotConsent)) }
                    }.disabled(!store.canStartRequest).accessibilityIdentifier("weekly.study-consent")
                    Text("Optional practice-study records describe choices such as reviewing rules. They exclude step totals, names, amounts and private notes. This choice starts off and is separate from agreeing to a challenge.")
                }
            }
        }
        .navigationTitle("Weekly challenges").daybreakScreenChrome()
        .refreshable { await store.refresh() }
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isLoading || store.isSending).accessibilityIdentifier("weekly.refresh") }
        .task(id: store.actorID) { await store.refresh() }
        .onChange(of: store.actorID) { _, _ in creation = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { creation = nil }
        }
        .sheet(item: $creation) { _ in WeeklyCreationView() }
    }
}
private struct WeeklyCreationSheet: Identifiable { let id = UUID() }

struct WeeklyDisclosure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Simulated stakes — no real money moves.").font(.subheadline.weight(.semibold))
            Text("Fictional practice data — Apple Health is not connected to weekly challenges.").font(.caption)
        }.accessibilityIdentifier("weekly.disclosure")
    }
}
struct WeeklyRecoverySection: View {
    let store: WeeklyStore
    var body: some View {
        if let request = store.pending {
            Section("Saved request") {
                Text(request.operation.summary)
                Text("We haven’t confirmed this update. Retry the same saved request to check what happened.")
                Button("Retry saved request") { Task { await store.retry() } }
                    .disabled(store.isLoading || store.isSending || store.storageBlocked).accessibilityIdentifier("weekly.retry")
                Button("Check or cancel saved request") { Task { await store.resolveSavedRequest() } }
                    .disabled(store.isLoading || store.isSending || store.storageBlocked).accessibilityIdentifier("weekly.resolve")
                Text("If it was saved, we recover its receipt. Otherwise we cancel that request safely so you can use your other choices.")
            }
        }
        if store.studyUnavailable { Section { Text("Optional study recording is unavailable. Your challenge, review and exit choices still work.") } }
        if let error = store.errorMessage {
            Section { Text(error).accessibilityIdentifier("weekly.error") }
        }
    }
}

struct WeeklyRulesView: View {
    let terms: WeeklyTerms
    let ownTarget: Int?
    private var f: WeeklyRuleFields { terms.fields }
    var body: some View {
        Section("This week’s rules") {
            Text("\((ownTarget ?? f.commonTargetSteps ?? 0).formatted()) steps in total").font(.headline)
            Text("From \(f.startsAt.text(zone: f.timezone))")
            Text("Until \(f.endsAt.text(zone: f.timezone))")
            Text("One shared calendar in \(f.timezone). Travel does not change it.")
            Text("$20 simulated entry · $0 fee · Nothing can be paid out or redeemed.")
            Text("All participants can meet their own target. Missing or incomplete step data alone never means a missed goal.")
            Text(f.isCommunity ? "Unclear results and safe exits return that person’s simulated entry before any bonus is calculated." : "If anyone’s result remains unclear or anyone leaves, this practice group ends without a simulated loss.")
            DisclosureGroup("Full weekly rules") {
                Text("Step totals come from fictional practice data. A reported progress update is not a qualifying result. Updated data may raise or lower progress before the result is confirmed.")
                Text("Initial updates close \(f.uploadClosesAt.text(zone: f.timezone)). Corrections close \(f.correctionsCloseAt.text(zone: f.timezone)).")
                Text("A saved result notice gives everyone 48 hours to ask for review. A reviewer has 72 hours after the filing window closes. If we cannot complete the full process, the affected result does not count against you.")
                Text("Result notices are due by \(f.lifecycle.noticeBy.text(zone: f.timezone)); the final deadline is \(f.lifecycle.finalityBy.text(zone: f.timezone)). A deadline never turns missing data into a miss.")
                Text("People who meet their target receive their simulated entry back and may equally share confirmed simulated losses. If everyone succeeds, there is no bonus. If nobody succeeds, no recipient is named. Leftover cents remain unallocated simulation.")
                Text("You can decline before acceptance, withdraw, or report an injury. Blocking removes social access; it does not rewrite saved results. Your own history and support remain private and available.")
                Text("Another week requires a new choice and fresh consent. A prior review may stay open while a later nonoverlapping week starts. Practice entry limits include earlier weeks still awaiting results.")
                if f.isCommunity { Text("This shared number is a configurable practice target. The community launch target has not been selected.") }
                else { Text("Practice groups currently support 2–5 people total, including the creator. Everyone accepts the same complete roster and targets.") }
            }
        }
    }
}

struct WeeklyCreationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    @State private var targets: [UUID: Int] = [:]
    @State private var week = Date().addingTimeInterval(7 * 86400)
    @State private var zone = "America/Chicago"
    @State private var consent = false
    private var store: WeeklyStore { model.weekly }
    private var draft: WeeklyDraft? {
        guard let actor = store.actorID else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt; formatter.dateFormat = "yyyy-MM-dd"
        let people = [actor] + selected.sorted { $0.uuidString < $1.uuidString }
        return WeeklyDraft(participants: people.map { .init(actorID: $0, targetSteps: targets[$0] ?? 7000) }, weekStart: formatter.string(from: week), timezone: zone)
    }
    var body: some View {
        NavigationStack {
            Form {
                WeeklyDisclosure()
                WeeklyRecoverySection(store: store)
                if let preview = store.previewed {
                    WeeklyRulesView(terms: preview.terms, ownTarget: preview.terms.fields.participants?.first { $0.id == store.actorID }?.targetSteps)
                    Section("Everyone’s target") {
                        ForEach(preview.terms.fields.participants ?? []) { p in
                            LabeledContent(name(p.id), value: "\(p.targetSteps.formatted()) steps")
                        }
                    }
                    Section {
                        Toggle("I agree to this week’s displayed targets, dates, fictional step source, simulated amounts, review and exit rules.", isOn: $consent)
                            .accessibilityIdentifier("weekly.create-consent")
                        Button("Create weekly invitation") { Task { await store.submit(.create(preview)) } }
                            .disabled(!consent || !store.canEnter).accessibilityIdentifier("weekly.create-confirm")
                        Button("Edit choices") { consent = false; store.invalidatePreview() }.disabled(store.isSending)
                    }
                } else if store.lastConfirmedOperation.map({ if case .create = $0 { true } else { false } }) == true,
                          let id = store.lastConfirmedID {
                    Section("Your week is saved") {
                        Text("Your friends still need to review and accept the same rules before the week can start.")
                        NavigationLink("Open your week") { WeeklyDetailView(challengeID: id) }
                        Button("Done") { dismiss() }
                    }
                } else {
                    Section("Choose 1–4 accepted friends") {
                        ForEach(store.friends, id: \.otherUserID) { friend in
                            Toggle(name(friend.otherUserID), isOn: Binding(get: { selected.contains(friend.otherUserID) }, set: { value in
                                if value { selected.insert(friend.otherUserID) } else { selected.remove(friend.otherUserID) }
                            })).disabled(!selected.contains(friend.otherUserID) && selected.count >= 4)
                        }
                        if store.friends.isEmpty { Text("No accepted friends are available. You can still join an open community week from Weekly challenges.") }
                    }
                    .disabled(store.isLoading || store.isSending)
                    Section("Week and targets") {
                        DatePicker("Monday start", selection: $week, in: Date()..., displayedComponents: .date)
                            .environment(\.timeZone, TimeZone(identifier: zone) ?? .gmt)
                        TextField("Calendar timezone", text: $zone).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if let actor = store.actorID { targetRow(actor) }
                        ForEach(selected.sorted { $0.uuidString < $1.uuidString }, id: \.self) { targetRow($0) }
                        Text("7,000 is an editable practice example, not a recommended health target. Choose a future Monday within four weeks.")
                        Button("Review this week’s rules") { if let draft { Task { await store.preview(draft) } } }
                            .disabled(selected.isEmpty || !store.canEnter || draft.map { (try? $0.validate(actorID: store.actorID!)) == nil } != false)
                            .accessibilityIdentifier("weekly.preview")
                    }.disabled(store.isLoading || store.isSending)
                }
            }.navigationTitle("Friend week").daybreakScreenChrome()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onAppear {
                    var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
                    let today = calendar.startOfDay(for: Date())
                    let weekday = calendar.component(.weekday, from: today)
                    week = calendar.date(byAdding: .day, value: (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7, to: today)!
                    store.beginCreation()
                }
                .onChange(of: draft) { _, _ in consent = false; store.invalidatePreview() }
                .onChange(of: store.actorID) { _, _ in dismiss() }
        }
    }
    private func name(_ id: UUID) -> String {
        if id == store.actorID { return "You" }
        return store.friends.first(where: { $0.otherUserID == id })?.displayName ?? "Invited friend"
    }
    private func targetRow(_ id: UUID) -> some View {
        TextField("\(name(id)) — steps", value: Binding(get: { targets[id] ?? 7000 }, set: { targets[id] = $0 }), format: .number).keyboardType(.numberPad)
    }
}

struct WeeklyDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var consent = false
    @State private var reviewReason: WeeklyReviewReason = .wrongTotal
    @State private var supportReason: WeeklySupportReason = .privacy
    @State private var exit: WeeklyExitKind?
    private var store: WeeklyStore { model.weekly }
    let challengeID: UUID
    var body: some View {
        List {
            WeeklyDisclosure()
            WeeklyRecoverySection(store: store)
            if let row = store.challenges.first(where: { $0.id == challengeID }) {
                WeeklyRulesView(terms: row.terms, ownTarget: row.own.targetSteps)
                if row.contactSuppressed { Section { Text("Shared participant details are hidden. Your own agreement history and safe choices remain available.") } }
                if row.mode == "friend" && !row.contactSuppressed {
                    Section("Everyone’s target") {
                        ForEach(Array(row.roster.enumerated()), id: \.element.id) { index, person in
                            LabeledContent(person.actorID == store.actorID ? "You" : person.displayName ?? "Participant \(index + 1)", value: "\(person.targetSteps.formatted()) steps")
                        }
                    }.accessibilityIdentifier("weekly.consent-roster")
                }
                if row.own.acceptedAt == nil && row.own.exitedAt == nil && ["invited", "scheduled"].contains(row.status) {
                    Section("Your invitation") {
                        Toggle("I agree to the complete displayed weekly rules and simulated amount.", isOn: $consent).accessibilityIdentifier("weekly.accept-consent")
                        Button("Accept this week") { Task { await store.submit(.accept(row.id, digest: row.termsDigest)) } }
                            .disabled(!consent || !store.canAccept(row.id) || !store.canEnter).accessibilityIdentifier("weekly.accept")
                        Button("Decline invitation") { exit = .decline }.disabled(!store.canDecline(row.id))
                    }
                }
                if row.own.acceptedAt == nil && row.own.exitedAt == nil && !["invited", "scheduled"].contains(row.status) {
                    Section("Invitation closed") {
                        Text("You did not join this week. No simulated entry was taken from you. Your own history and support remain available.")
                    }
                }
                Section("Your progress") {
                    if let progress = row.ownProgress, let updated = progress.updatedAt {
                        Text("\(progress.observedSteps.formatted()) reported practice steps")
                        Text("Updated \(updated.text(zone: row.terms.fields.timezone))")
                        Text("Reported progress does not decide your result. It can change when another update is saved.")
                        if let qualifying = progress.qualifyingSteps {
                            Text("Steps that count in this practice week: \(qualifying.formatted())")
                            Text("This is fictional practice data. It remains subject to correction and review.")
                        }
                    } else { Text("No practice step update is available yet. Missing data alone never means you missed the goal.") }
                }
                ForEach(row.notices) { notice in
                    Section("Saved result update") {
                        Text(notice.qualification.provisionalTitle).font(.headline)
                        Text("Saved \(notice.recordedAt.text(zone: row.terms.fields.timezone))")
                        Text("Ask for review by \(notice.fileBy.text(zone: row.terms.fields.timezone))")
                        Text("This update is provisional. Your final result and simulated return are recorded separately.")
                        Picker("Review reason", selection: $reviewReason) { ForEach(WeeklyReviewReason.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Button("Ask us to review this update") { Task { await store.submit(.review(row.id, revision: notice.revision, reason: reviewReason)) } }
                            .disabled(!store.canReview(row.id, revision: notice.revision)).accessibilityIdentifier("weekly.review")
                    }
                }
                ForEach(row.cases) { review in
                    Section("Your review request") {
                        Text(review.reason.title)
                        Text(review.resolution == nil ? "Your review request is saved. Settlement is paused." : review.resolution == "upheld" ? "Review complete — result upheld" : "Review complete — this week won’t count against you")
                    }
                }
                if let result = row.result {
                    Section("Confirmed result") { Text(result.qualification.title); Text(result.recordedAt.text(zone: row.terms.fields.timezone)) }
                    Section("Simulated return") {
                        if let allocation = row.allocation {
                            Text("Entry returned: \(money(allocation.returnedCents))")
                            Text("Additional simulated bonus: \(money(allocation.bonusCents))")
                            Text("Nothing can be paid out or redeemed. No real money moved.")
                        } else { Text("Result confirmed — simulated return update pending.") }
                    }
                }
                WeeklySharingSection(store: store, row: row)
                Section("Your choices") {
                    if row.own.acceptedAt != nil && row.result == nil && row.own.exitedAt == nil {
                        Button("Withdraw from this week") { exit = .withdrawal }.disabled(!store.canExit(row.id))
                        Button("Report an injury") { exit = .injury }.disabled(!store.canExit(row.id))
                    }
                    ForEach(row.exits) { _ in Text("Your exit is saved. The final result and simulated return are recorded separately.") }
                    Picker("Support topic", selection: $supportReason) { ForEach(WeeklySupportReason.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Button("Save support request") { Task { await store.submit(.support(row.id, reason: supportReason)) } }
                        .disabled(!store.canStartRequest || !store.freshIDs.contains(row.id)).accessibilityIdentifier("weekly.support")
                    ForEach(row.support) { receipt in Text("Saved: \(receipt.reason.title)") }
                    Text("These practice support records stay local. They do not contact an external support team.")
                    NavigationLink("Choose a new friend week") { WeeklyCreationView() }.disabled(!store.canEnter)
                    Text("A new week never renews automatically. Your earlier review stays open on its original terms.")
                }
            } else { Text("Refresh to load your current weekly agreement and choices.") }
        }.navigationTitle("Your week").daybreakScreenChrome()
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isSending || store.isLoading) }
            .confirmationDialog("Leave this week?", isPresented: Binding(get: { exit != nil }, set: { if !$0 { exit = nil } })) {
                if let exit { Button("Confirm exit") { Task { await store.submit(.exit(challengeID, kind: exit)); self.exit = nil } } }
                Button("Keep participating", role: .cancel) { exit = nil }
            } message: { Text("Confirming asks us to save your exit without a simulated loss. For a friend week, the whole group ends without a simulated loss. No medical details are needed.") }
            .onChange(of: store.actorID) { _, _ in consent = false; exit = nil }
    }
    private func money(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}

struct WeeklyCohortView: View {
    @Environment(AppModel.self) private var model
    @State private var consent = false
    let cohortID: UUID
    private var store: WeeklyStore { model.weekly }
    var body: some View {
        List {
            WeeklyDisclosure(); WeeklyRecoverySection(store: store)
            if let own = store.challenges.first(where: { $0.id == cohortID }) {
                Section("You joined this week") { NavigationLink("Open your community week") { WeeklyDetailView(challengeID: own.id) } }
            } else if let cohort = store.cohorts.first(where: { $0.id == cohortID }) {
                WeeklyRulesView(terms: cohort.terms, ownTarget: cohort.terms.fields.commonTargetSteps)
                Section("Join this week") {
                    Text("\(cohort.participantCount) joined · \(cohort.capacity) places")
                    Text("Join before \(cohort.joinBy.text(zone: cohort.terms.fields.timezone)). At least two people must join; otherwise the week ends with no simulated loss.")
                    Text("Joining does not share your steps with strangers or create friendships.")
                    Toggle("I agree to the common weekly target, displayed rules and simulated amount.", isOn: $consent).accessibilityIdentifier("weekly.join-consent")
                    Button("Join community week") { Task { await store.submit(.join(cohort.id, digest: cohort.termsDigest)) } }
                        .disabled(!consent || !store.canEnter || cohort.participantCount >= cohort.capacity).accessibilityIdentifier("weekly.join")
                }
            } else { Text("This community week is not available. Refresh Weekly challenges to see current choices.") }
        }.navigationTitle("Community week").daybreakScreenChrome()
            .onChange(of: store.actorID) { _, _ in consent = false }
    }
}

struct WeeklySharingSection: View {
    let store: WeeklyStore
    let row: WeeklyChallenge
    var body: some View {
        Section("Share selected progress") {
            Text("Choose an accepted friend to offer your reported practice steps and target for this week. They choose whether to follow. Results, reviews and simulated amounts stay private.")
            ForEach(store.friends, id: \.otherUserID) { friend in
                let grant = store.sharing[row.id]?.first { $0.friendID == friend.otherUserID }
                VStack(alignment: .leading) {
                    Text(friend.displayName).font(.headline)
                    if let grant, grant.enabled {
                        Text(grant.state == "accepted" ? "Your friend follows this week’s reported progress." : "Your friend has not accepted the offer yet.")
                        Button("Stop sharing with \(friend.displayName)") { Task { await store.submit(.share(row.id, friendID: friend.otherUserID, enabled: false)) } }
                            .disabled(!store.canStartRequest)
                    } else if grant?.state == "declined" { Text("Your friend chose not to follow this week.") }
                    else {
                        Button("Offer progress to \(friend.displayName)") { Task { await store.submit(.share(row.id, friendID: friend.otherUserID, enabled: true)) } }
                            .disabled(!store.canStartRequest || row.own.acceptedAt == nil || row.contactSuppressed)
                    }
                }
            }
        }
    }
}
struct WeeklyFollowingSections: View {
    let store: WeeklyStore
    var body: some View {
        if !store.followRequests.isEmpty {
            Section("Progress offers") {
                ForEach(store.followRequests) { offer in
                    Text("\(offer.displayName) offers their reported practice progress for one week.")
                    Text("Following is optional. It does not enter you in their challenge or share your steps.")
                    Button("Follow \(offer.displayName) this week") { Task { await store.submit(.follow(offer.challengeID, ownerID: offer.ownerID, offerID: offer.offerID, decision: .accept)) } }.disabled(!store.canStartRequest)
                    Button("Decline progress offer") { Task { await store.submit(.follow(offer.challengeID, ownerID: offer.ownerID, offerID: offer.offerID, decision: .decline)) } }.disabled(!store.canStartRequest)
                }
            }
        }
        if !store.sharedProgress.isEmpty {
            Section("Friends you follow") {
                ForEach(store.sharedProgress) { progress in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(progress.displayName).font(.headline)
                        Text("Weekly target: \(progress.targetSteps.formatted()) steps")
                        if let steps = progress.observedSteps { Text("\(steps.formatted()) reported practice steps") }
                        else { Text("No reported update is available. This does not mean a missed goal.") }
                        if let updated = progress.updatedAt { Text("Updated \(updated.text(zone: progress.timezone))") }
                        Text("Reported progress is separate from qualifying results. Following ends with this chosen week; another week needs fresh consent.")
                        Button("Stop following \(progress.displayName)") { Task { await store.submit(.follow(progress.challengeID, ownerID: progress.ownerID, offerID: progress.offerID, decision: .unfollow)) } }.disabled(!store.canStartRequest)
                    }
                }
            }
        }
    }
}
#endif
