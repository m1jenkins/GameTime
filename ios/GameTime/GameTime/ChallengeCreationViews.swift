import SwiftUI
import GameTimeCore

struct ChallengeV1Create: View {
    @Bindable var store: ChallengeV1Store
    let profile: UserProfile?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.challengeHealthFlow) private var health
    private let onGoHome: () -> Void
    @State private var draft: ChallengeCreationDraft
    private enum Editor: String, Identifiable { case dates, amount; var id: String { rawValue } }
    @State private var editor: Editor?
    @State private var focusedInput: String?
    @State private var keyboardVisible = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var headingFocused: Bool
    init(store: ChallengeV1Store, initialPolicy: ChallengeV1Policy? = nil, allowed: Set<String>? = nil,
         profile: UserProfile? = nil, onGoHome: @escaping () -> Void = {}) {
        let draft: ChallengeCreationDraft
        #if DEBUG
        if LiveDesignFixtures.round13 {
            draft = ChallengeCreationDraft(initialPolicy: initialPolicy, allowed: allowed,
                                           now: LiveDesignFixtures.now.date, zone: "America/Los_Angeles")
            if draft.metrics.contains(.distance) { draft.metric = .distance }
        } else { draft = ChallengeCreationDraft(initialPolicy: initialPolicy, allowed: allowed) }
        #else
        draft = ChallengeCreationDraft(initialPolicy: initialPolicy, allowed: allowed)
        #endif
        self.init(store: store, draft: draft, profile: profile, onGoHome: onGoHome)
    }
    init(store: ChallengeV1Store, draft: ChallengeCreationDraft, profile: UserProfile? = nil, onGoHome: @escaping () -> Void = {}) {
        self.store = store
        self.profile = profile
        self.onGoHome = onGoHome
        _draft = State(initialValue: draft)
    }
    private var heading: String {
        switch draft.step {
        case .type: "Who’s it for?"
        case .activity: "What’s your goal?"
        case .review: draft.mode == .personal ? "Review your goal." : "Make it a challenge."
        }
    }
    private var ready: Bool { health == nil || draft.healthBinding(actor: store.actor).map { health?.canConsent($0) == true } == true }
    private var blocked: Bool { store.busy || draft.reading || !draft.initialized || (store.pending == nil && draft.unavailable) }
    var body: some View {
        NavigationStack {
            if let receipt = draft.receipt, let id = receipt.id {
                if draft.savedPolicy?.mode == .friend {
                    ChallengeCreationInviteView(store: store, challengeID: id, progressLabels: progressLabels, profile: profile, onGoHome: onGoHome)
                } else {
                    ChallengeCreationSuccess(store: store, challengeID: id, onGoHome: onGoHome)
                }
            } else {
                flow
            }
        }
        .tint(Floodlight.link)
        .onChange(of: store.actor) { draft.close(); dismiss() }
        .onDisappear { draft.close() }
        .task { await draft.initialize(store: store, health: health) }
    }
    private var flow: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: draft.step == .review && draft.mode == .friend && draft.competition == .goal && !typeSize.isAccessibilitySize ? 8 : 14) {
                    progress.id("creation-top")
                    FloodlightTitle(heading, size: 36)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                        .accessibilityIdentifier("beta.create.heading")
                    Group {
                        switch draft.step {
                        case .type: typeStep
                        case .activity: activityStep
                        case .review: reviewStep
                        }
                    }.disabled(store.pending != nil || store.busy)
                    if let error = draft.error {
                        Text(error).font(.subheadline).foregroundStyle(SignalCreationTheme.danger)
                            .accessibilityIdentifier("beta.personal.preview.error")
                    }
                    if let error = store.error { Text(error).font(.subheadline).foregroundStyle(SignalCreationTheme.danger) }
                    if store.pending != nil {
                        Text(ChallengePendingCopy.title).font(.subheadline.weight(.semibold))
                        Text(ChallengePendingCopy.message).font(.subheadline)
                        Button(ChallengePendingCopy.cancel) { Task { await store.abandon(); draft.consent = false } }
                            .buttonStyle(LiveSecondaryButtonStyle()).disabled(store.busy)
                    }
                    if draft.reading { ProgressView("Loading the rules…") }
                    if store.busy { ProgressView("Saving…") }
                    if draft.step == .review && store.access?.ageConfirmed != true {
                        Text("Confirm that you are 21 or older in Challenges before continuing.").font(.subheadline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Floodlight.ink)
            .modifier(ChallengeScrollLegibility())
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                FloodlightCreationChrome(title: draft.step != .type && draft.mode == .personal ? "Personal goal" : "Create challenge",
                                     showsBack: draft.step != draft.firstStep,
                                     back: { if !store.busy { draft.back() } }, close: { dismiss() })
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                primaryAction.padding(.horizontal, 16)
                    .padding(.top, 10).padding(.bottom, 6).background(Floodlight.ground)
                    .overlay(alignment: .top) { Rectangle().fill(Floodlight.line).frame(height: 1) }
            }
            .onChange(of: draft.step) {
                proxy.scrollTo("creation-top", anchor: .top)
                headingFocused = true
            }
            .onChange(of: focusedInput) { _, field in
                if keyboardVisible, let field { proxy.scrollTo(field, anchor: .center) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                keyboardVisible = true
                if let focusedInput { proxy.scrollTo(focusedInput, anchor: .center) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
            .sheet(item: $editor) { editor in
                switch editor {
                case .dates: datesEditor
                case .amount:
                    SignalAmountEditor(value: draft.dollars, committed: draft.commits) { amount in
                        guard amount != draft.dollars else { return }
                        draft.dollars = amount
                        Task { await draft.review(store: store) }
                    }
                }
            }
        }.background(FloodlightCreationBackdrop())
    }
    private var progress: some View {
        FloodlightCreationProgress(labels: progressLabels, current: draft.progress - 1)
            .accessibilityIdentifier("beta.create.progress")
    }
    private var progressLabels: [String] {
        let stages = draft.mode == .personal ? ["Goal", "Rules"] : ["Goal", "Challenge", "Friends"]
        return draft.directEntry ? stages : ["Who"] + stages
    }
    private var typeStep: some View {
        VStack(spacing: 0) {
            if draft.permits(.personal, .goal) {
                choice("Personal goal", detail: "Just for you", symbol: "person", selected: draft.mode == .personal, id: "personal") { draft.mode = .personal }
            }
            if draft.permits(.friend, .goal) {
                if draft.permits(.personal, .goal) { Rectangle().fill(Floodlight.line).frame(height: 1) }
                choice("Goals with friends", detail: "Each person chooses a goal", symbol: "person.2", selected: draft.mode == .friend && draft.competition == .goal, id: "friend") { draft.mode = .friend; draft.competition = .goal }
            }
            if draft.permits(.friend, .leaderboard) {
                if draft.permits(.personal, .goal) || draft.permits(.friend, .goal) { Rectangle().fill(Floodlight.line).frame(height: 1) }
                choice("Friend leaderboard", detail: "Compare saved results", symbol: "chart.bar", selected: draft.mode == .friend && draft.competition == .leaderboard, id: "leaderboard") { draft.mode = .friend; draft.competition = .leaderboard }
            }
        }.floodlightHero()
    }
    private func choice(_ title: String, detail: String, symbol: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FloodlightCreationIcon(symbol: symbol, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).floodlightFont(16, weight: .semibold)
                    Text(detail).floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.heroMuted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 21, weight: .medium))
                    .foregroundStyle(selected ? Floodlight.link : Floodlight.heroMuted).accessibilityHidden(true)
            }.foregroundStyle(Floodlight.ink).padding(.horizontal, 15).padding(.vertical, 20)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("beta.create.type." + id)
    }
    @ViewBuilder private var activityStep: some View {
        // Only the activities the server allows for this kind of challenge.
        // A personal distance goal is Outdoor runs.
        VStack(alignment: .leading, spacing: 13) {
            FloodlightCreationActivityChoices(selection: $draft.metric,
                                  metrics: draft.mode == .personal ? draft.metrics.sorted { $0 == .distance && $1 != .distance } : draft.metrics) { metric in
                draft.mode == .personal && metric == .distance ? "Outdoor runs" : metric.title
            }
        if draft.unavailable {
            Text("Activity not available yet. Choose another activity to continue.").font(.subheadline)
        } else {
            if draft.metric == .timed {
                SignalNumberEntry(text: $draft.distance, title: "Whole run", unit: "kilometres", id: "beta.create.distance", keyboard: .decimalPad,
                                  focusChanged: { inputFocus($0, id: "beta.create.distance") })
            }
            if draft.mode == .personal {
                SignalCreationGoalEntry(text: $draft.target, metric: draft.metric, duration: draft.duration,
                                        sourceLabel: health == nil ? nil : "Apple Watch", id: "beta.create.target",
                                        focusChanged: { inputFocus($0, id: "beta.create.target") })
                if let health, let binding = draft.planningBinding(actor: store.actor) {
                    ChallengeHealthSuggestionView(flow: health, binding: binding, policy: draft.policy, days: draft.duration ?? 7) {
                        draft.target = draft.metric.inputValue($0)
                    }.buttonStyle(SignalCreationTextActionStyle())
                }
            } else {
                Rectangle().fill(Floodlight.line).frame(height: 1)
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        FloodlightOrb(slot: 0, initials: ownInitials, size: 34)
                        FloodlightOrb(slot: 1, initials: "+", size: 34, waiting: true)
                        FloodlightOrb(slot: 2, initials: "+", size: 34, waiting: true)
                    }
                    Text(draft.policy.hasTarget ? "Everyone chooses their goal in the lobby." : draft.policy.scoring)
                        .floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        }.padding(15).floodlightHero()
        datesSummary
    }
    private func inputFocus(_ focused: Bool, id: String) {
        if focused { focusedInput = id }
        else if focusedInput == id { focusedInput = nil }
    }
    private var datesSummary: some View {
        FloodlightCreationDateCard(start: draft.start, duration: draft.duration, calendar: draft.calendar, timeZoneID: draft.zone) { editor = .dates }
    }
    private var dateRange: String {
        let formatter = DateFormatter()
        formatter.timeZone = draft.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        guard let duration = draft.duration,
              let last = draft.calendar.date(byAdding: .day, value: duration - 1, to: draft.start) else { return "Choose 1 to 30 full days" }
        return formatter.string(from: draft.start) + " – " + formatter.string(from: last)
    }
    private var datesEditor: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Duration in full days").font(.headline)
                        HStack(spacing: 16) {
                            adjust("Fewer days", symbol: "minus", id: "beta.stepper.days-Decrement", disabled: (draft.duration ?? 1) <= 1) { draft.days = String(max(1, (draft.duration ?? 7) - 1)) }
                            TextField("Days", text: $draft.days).keyboardType(.numberPad).multilineTextAlignment(.center)
                                .font(.title2.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityLabel("Duration in full days").accessibilityIdentifier("beta.create.days")
                            adjust("More days", symbol: "plus", id: "beta.stepper.days-Increment", disabled: (draft.duration ?? 30) >= 30) { draft.days = String(min(30, (draft.duration ?? 7) + 1)) }
                        }.modifier(SignalGlassGroup())
                    }
                    DatePicker("Starts", selection: $draft.start, in: draft.allowedDates, displayedComponents: .date)
                        .environment(\.timeZone, draft.calendar.timeZone)
                        .font(.headline).accessibilityIdentifier("beta.create.start")
                    NavigationLink {
                        SignalTimeZonePicker(selection: $draft.zone)
                    } label: {
                        HStack {
                            Label(SignalTimeZone.name(draft.zone), systemImage: "globe")
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Time zone, " + SignalTimeZone.name(draft.zone)).accessibilityIdentifier("beta.create.zone")
                    if let window = draft.window { SignalDateSpan(window: window) }
                    Text("Start in 2–30 days; each day runs midnight to midnight.").font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                    if let error = draft.error { Text(error).font(.subheadline).foregroundStyle(SignalCreationTheme.danger) }
                }.padding(SignalCreationTheme.contentInset)
            }.background(SignalCreationTheme.canvas).foregroundStyle(SignalCreationTheme.textPrimary)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Dates").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if draft.validate(.dates) { editor = nil }
                        }.accessibilityIdentifier("beta.create.dates.done")
                    }
                }
        }.tint(SignalCreationTheme.accent)
    }
    private func adjust(_ title: String, symbol: String, id: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }.accessibilityLabel(title)
            .modifier(SignalCircleAction()).disabled(disabled).accessibilityIdentifier(id)
    }
    @ViewBuilder private var reviewStep: some View {
        if draft.mode == .friend, draft.competition == .goal {
            friendReview
        } else { retainedReview }
    }
    private var ownInitials: String {
        FloodlightOrb.initials(profile?.displayName ?? profile?.handle ?? "You")
    }
    @ViewBuilder private var friendReview: some View {
        if let window = draft.window {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 1) {
                    FloodlightLabel("Simulated amount")
                    Text(LiveChallengePresentation.money(window.amountCents)).floodlightFont(56, weight: .semibold, condensed: true, maxScale: 1.5)
                        .foregroundStyle(Floodlight.ink)
                    Text("each · Fee $0").floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.heroMuted)
                    Button("Edit") { editor = .amount }.floodlightFont(13.5, weight: .semibold)
                        .buttonStyle(.plain).foregroundStyle(Floodlight.link).frame(minHeight: 32, alignment: .leading)
                        .accessibilityLabel("Edit simulated amount").accessibilityIdentifier("beta.create.edit-amount")
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 4) {
                    FloodlightCreationPot(cents: window.amountCents, initials: ownInitials, caption: true).frame(width: 115)
                    Text("Just you so far").floodlightFont(12, weight: .semibold).foregroundStyle(Floodlight.heroMuted)
                }
            }.padding(15).floodlightHero().accessibilityElement(children: .contain).accessibilityIdentifier("beta.create.amount-card")
            Text("No real money moves. Nothing can be paid out or redeemed.")
                .floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    FloodlightCreationIcon(symbol: draft.metric.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.metric.title).floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                        Text(compactDateRange + " · " + FloodlightCreationDateCard.zoneName(draft.zone))
                            .floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Edit") { draft.back() }.floodlightFont(13, weight: .semibold).foregroundStyle(Floodlight.link)
                        .buttonStyle(.plain).frame(minWidth: 32, minHeight: 44)
                        .accessibilityLabel("Edit goal and dates").accessibilityIdentifier("beta.create.edit-goal")
                }.padding(.horizontal, 15).padding(.vertical, 9)
                Rectangle().fill(Floodlight.line).frame(height: 1)
                HStack(spacing: 12) {
                    FloodlightCreationIcon(symbol: "lock")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private challenge").floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                        Text("Only people you select can join.").floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 15).padding(.vertical, 9)
            }.floodlightCard()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(FloodlightChallengeFacts.outcomes(pair: false)) { outcome in
                    VStack(spacing: 4) {
                        FloodlightOutcomePicture(outcome: outcome.kind, pair: false).frame(width: 72)
                        Text(outcome.title).floodlightFont(12.5, weight: .semibold).foregroundStyle(Floodlight.ink)
                        Text(outcome.short).floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                    }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 6)
                        .floodlightCard(radius: 18, fill: outcome.kind == .unconfirmed ? Floodlight.unconfirmedWash : Floodlight.card,
                                        dashedEdge: outcome.kind == .unconfirmed ? Floodlight.unconfirmed : nil)
                }
            }
            DisclosureGroup("Full challenge rules") {
                ChallengeAgreementText(policy: draft.policy, window: window, minimum: 2, sourcePolicy: health != nil ? draft.source?.identifier : nil)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }.disclosureGroupStyle(FloodlightCreationRulesStyle()).accessibilityIdentifier("beta.create.rules")
        }
    }
    private var compactDateRange: String {
        guard let duration = draft.duration, let last = draft.calendar.date(byAdding: .day, value: duration - 1, to: draft.start) else { return dateRange }
        let formatter = DateFormatter(); formatter.calendar = draft.calendar; formatter.timeZone = draft.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        let start = formatter.string(from: draft.start)
        let sameMonth = draft.calendar.component(.month, from: draft.start) == draft.calendar.component(.month, from: last)
        let end = sameMonth ? String(draft.calendar.component(.day, from: last)) : formatter.string(from: last)
        return start + "–" + end + ", " + String(draft.calendar.component(.year, from: last))
    }
    @ViewBuilder private var retainedReview: some View {
        if let window = draft.window {
            VStack(alignment: .leading, spacing: 8) {
                if draft.mode == .personal, let value = draft.metric.parse(draft.target) {
                    Text(draft.metric.display(value)).font(.subheadline.weight(.semibold))
                } else {
                    Label(draft.metric.title, systemImage: draft.metric.symbol).font(.subheadline.weight(.semibold))
                }
                Text(dateRange + " · " + SignalTimeZone.name(draft.zone))
                    .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                Button("Edit goal and dates") { draft.back() }.font(.caption.weight(.semibold))
                    .buttonStyle(.plain).foregroundStyle(SignalCreationTheme.accent).frame(minHeight: 44)
                    .accessibilityIdentifier("beta.create.edit-goal")
            }
            if draft.mode == .friend {
                Label("Private challenge", systemImage: "lock").font(.subheadline.weight(.semibold))
                Text("Only people you select can join. Everyone reviews the roster and rules before agreeing.")
                    .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            if draft.mode == .personal, draft.canCommit {
                ChallengeCommitmentSection(draft: draft, store: store)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Your agreement").font(.subheadline.weight(.semibold)).padding(.bottom, 2)
                reviewFact("Activity counted", text: health == nil ? "Fictional activity for this local preview. No Apple Health activity is scored." : ChallengeHealthCopy.source(draft.source?.identifier ?? ""))
                if health != nil, store.availability?.accountMode == true {
                    reviewFact("How scores are checked", text: ChallengeHealthCopy.accountMode)
                }
                reviewFact("Possible results", text: draft.mode == .personal
                           ? (draft.commits
                              ? "Meet your goal: $0 test charge. If your full Apple Health total falls short, GameTime makes one test charge after the review window and keeps it. Missing or partial activity never counts as a miss."
                              : "Meet your goal and your simulated entry returns. A confirmed miss leaves it unallocated. Missing or unclear activity never proves a miss.")
                           : draft.policy.allocation)
                Button { editor = .amount } label: {
                    HStack(spacing: 8) {
                        SignalCreationAgreementRow(symbol: "dollarsign", title: draft.commits ? "Test commitment" : "Simulated amount",
                                                   detail: challengeMoney(window.amountCents) + (draft.commits ? " · charged only if you miss" : " · Fee $0"))
                        Text("Edit").font(.caption.weight(.semibold)).foregroundStyle(SignalCreationTheme.accent).padding(.trailing, 14)
                    }.background(SignalCreationTheme.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("beta.create.edit-amount")
                Text(draft.commits ? ChallengeCommitment.banner : "No real money moves. Nothing can be paid out or redeemed.")
                    .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary).padding(.top, 2)
            }
            if draft.metric == .timed, let distance = window.distanceMm {
                if health != nil {
                    reviewFact("Whole run distance", text: "\(ChallengeTimedDistanceCopy.range(distance)), including both distances. The whole run must fit inside these dates.")
                } else {
                    Text("Whole run: " + ChallengeV1Policy.Metric.distance.display(distance)).font(.subheadline)
                }
            }
            DisclosureGroup(draft.mode == .personal ? "Full goal rules" : "Full challenge rules") {
                ChallengeAgreementText(policy: draft.policy, window: window, minimum: draft.mode == .personal ? 1 : 2, sourcePolicy: health != nil ? draft.source?.identifier : nil)
                    .padding(.top, 12)
                if draft.mode == .personal {
                    Text("You can leave before the result is final. You have 48 hours after the result notice to ask for a review.")
                        .font(.subheadline).padding(.top, 8)
                }
            }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("beta.create.rules")
            if draft.mode == .personal {
                if let health, let binding = draft.healthBinding(actor: store.actor) {
                    ChallengeHealthStatusView(flow: health, binding: binding, readiness: true).buttonStyle(LiveSecondaryButtonStyle())
                }
                if draft.needsReview {
                    Text("Your goal changed. Refresh the review before you agree.").font(.subheadline)
                }
                if draft.commits, draft.commitmentSaved {
                    Text(ChallengeCommitment.consent(amountCents: window.amountCents)).font(.subheadline)
                        .accessibilityIdentifier("beta.personal.commitment.consent")
                }
                Toggle("I have read the complete rules and agree", isOn: $draft.consent)
                    .disabled(draft.needsReview || draft.reading)
                    .font(.body).accessibilityIdentifier("beta.personal.consent")
            }
        }
    }
    private func reviewFact(_ title: String, text: String) -> some View {
        SignalCreationAgreementRow(symbol: title == "Activity counted" ? "applewatch" : title == "Whole run distance" ? "figure.run" : "checkmark.shield", title: title, detail: text)
    }
    private var isReviewAction: Bool { draft.step == .activity || draft.step == .review && draft.needsReview }
    private var primaryTitle: String {
        if store.pending != nil { return ChallengePendingCopy.retry }
        if isReviewAction { return draft.step == .review ? "Refresh review" : "Continue" }
        if draft.step == .review { return draft.mode == .personal ? "Create personal goal" : "Continue to invite" }
        return "Continue"
    }
    private var showsForwardArrow: Bool {
        store.pending == nil && (draft.step != .review || draft.mode == .friend && !isReviewAction)
    }
    private var primaryAction: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task {
                if store.pending != nil || draft.step == .review && !draft.needsReview { await draft.submit(store: store) }
                else { await draft.advance(store: store) }
                if let error = draft.error { SignalAccessibility.announce(error) }
            }
        } label: {
            HStack {
                Text(primaryTitle)
                if showsForwardArrow { Image(systemName: "arrow.right").accessibilityHidden(true) }
            }
        }
        .buttonStyle(FloodlightPrimaryButtonStyle())
        .disabled(blocked || (store.pending == nil && draft.step == .review && !draft.needsReview && (store.access?.ageConfirmed != true || draft.mode == .personal && (!draft.consent || !ready || draft.commits && !draft.commitmentSaved))))
        .accessibilityIdentifier(store.pending != nil ? "beta.create.retry" : isReviewAction && draft.mode == .personal ? "beta.personal.preview" : draft.step == .review ? (draft.mode == .personal ? "beta.personal.commit" : "beta.create.submit") : "beta.create.continue")
    }
}
