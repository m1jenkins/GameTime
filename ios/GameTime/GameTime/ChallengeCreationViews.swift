import SwiftUI
import GameTimeCore

struct ChallengeV1Create: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.challengeHealthFlow) private var health
    @State private var draft: ChallengeCreationDraft
    @State private var zonePicker = false
    @ScaledMetric(relativeTo: .title3) private var choiceSymbolWidth: CGFloat = 28
    @State private var showSuggestion = false
    @AccessibilityFocusState private var headingFocused: Bool
    init(store: ChallengeV1Store, initialPolicy: ChallengeV1Policy? = nil, personalStepsOnly: Bool = false) {
        self.init(store: store, draft: ChallengeCreationDraft(initialPolicy: initialPolicy, personalStepsOnly: personalStepsOnly))
    }
    init(store: ChallengeV1Store, draft: ChallengeCreationDraft) {
        self.store = store
        _draft = State(initialValue: draft)
    }
    private var heading: String {
        switch draft.step {
        case .type: "Who’s it for?"
        case .activity: draft.mode == .personal ? "Choose your goal." : "Choose your activity."
        case .dates: "Set the dates."
        case .amount: "Choose your amount."
        case .review: draft.mode == .personal ? "Review your goal." : "Review your challenge."
        }
    }
    private var ready: Bool { health == nil || draft.healthBinding(actor: store.actor).map { health?.canConsent($0) == true } == true }
    private var blocked: Bool { store.busy || draft.reading || !draft.initialized || (store.pending == nil && draft.unavailable) }
    var body: some View {
        NavigationStack {
            if let receipt = draft.receipt, let id = receipt.id {
                saved(id: id, status: receipt.status ?? "scheduled")
            } else {
                flow
            }
        }
        .tint(SignalTheme.accent)
        .onChange(of: store.actor) { draft.close(); dismiss() }
        .onDisappear { draft.close() }
        .task { await draft.initialize(store: store, health: health) }
    }
    private var flow: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    progress.id("creation-top")
                    Text(heading).font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                        .accessibilityIdentifier("beta.create.heading")
                    Group {
                        switch draft.step {
                        case .type: typeStep
                        case .activity: activityStep
                        case .dates: datesStep
                        case .amount: amountStep
                        case .review: reviewStep
                        }
                    }.disabled(store.pending != nil || store.busy)
                    if let error = draft.error {
                        Text(error).font(.subheadline).foregroundStyle(SignalTheme.danger)
                            .accessibilityIdentifier("beta.personal.preview.error")
                    }
                    if let error = store.error { Text(error).font(.subheadline).foregroundStyle(SignalTheme.danger) }
                    if store.pending != nil {
                        Text("Your last action is saved on this phone. Retry it to check whether it went through.").font(.subheadline)
                        Button("Stop waiting for this action") { Task { await store.abandon(); draft.consent = false } }
                            .buttonStyle(SignalSecondaryButtonStyle()).disabled(store.busy)
                    }
                    if draft.reading { ProgressView("Loading your agreement…") }
                    if store.busy { ProgressView("Saving your action…") }
                    if draft.step == .review && store.access?.ageConfirmed != true {
                        Text("Confirm that you are 21 or older in Challenges before continuing.").font(.subheadline)
                    }
                    primaryAction
                }
                .padding(SignalTheme.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SignalTheme.canvas)
            .foregroundStyle(SignalTheme.textPrimary)
            .modifier(ChallengeScrollLegibility())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.mode == .personal ? "Personal goal" : "Create a challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if draft.step == draft.firstStep { dismiss() } else { draft.back() }
                    } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Back").modifier(SignalNavigationAction()).accessibilityIdentifier("beta.create.back").disabled(store.busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close").modifier(SignalNavigationAction()).accessibilityIdentifier("beta.create.close")
                }

            }
            .onChange(of: draft.step) {
                proxy.scrollTo("creation-top", anchor: .top)
                headingFocused = true
            }
            .sheet(isPresented: $zonePicker) { SignalTimeZonePicker(selection: $draft.zone) }
        }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                ForEach(1...draft.stepCount, id: \.self) { index in
                    Rectangle().fill(index <= draft.progress ? SignalTheme.accent : SignalTheme.divider).frame(height: 3)
                }
            }.accessibilityHidden(true)
            Text("Step \(draft.progress) of \(draft.stepCount)").font(.caption).foregroundStyle(SignalTheme.textSecondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Step \(draft.progress) of \(draft.stepCount)")
            .accessibilityIdentifier("beta.create.progress")
    }
    private var typeStep: some View {
        VStack(spacing: 0) {
            choice("Personal goal", detail: "Just for you", symbol: "person", selected: draft.mode == .personal, id: "personal") { draft.mode = .personal }
            choice("Goals with friends", detail: "Each person chooses a goal", symbol: "person.2", selected: draft.mode == .friend && draft.competition == .goal, id: "friend") { draft.mode = .friend; draft.competition = .goal }
            choice("Friend leaderboard", detail: "Compare saved results", symbol: "chart.bar", selected: draft.mode == .friend && draft.competition == .leaderboard, id: "leaderboard") { draft.mode = .friend; draft.competition = .leaderboard }
        }
    }
    private func choice(_ title: String, detail: String, symbol: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title3).frame(width: choiceSymbolWidth).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? SignalTheme.accent : SignalTheme.textSecondary).accessibilityHidden(true)
            }.foregroundStyle(SignalTheme.textPrimary).padding(.vertical, 20).contentShape(Rectangle())
                .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.divider).frame(height: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("beta.create.type." + id)
    }
    @ViewBuilder private var activityStep: some View {
        if !draft.personalStepsOnly { SignalActivityChoices(selection: $draft.metric) }
        if draft.unavailable {
            Text("Activity not available yet. Choose another activity to continue.").font(.subheadline)
        } else {
            if draft.metric == .timed {
                SignalNumberEntry(text: $draft.distance, title: "Whole run", unit: "kilometres", id: "beta.create.distance", keyboard: .decimalPad)
            }
            if draft.mode == .personal {
                SignalNumberEntry(text: $draft.target, title: draft.metric == .timed ? "Time to beat" : "Your goal", unit: goalUnit,
                                  id: "beta.create.target", keyboard: draft.metric == .steps ? .numberPad : draft.metric == .distance ? .decimalPad : .numbersAndPunctuation)
                if let health, let binding = draft.planningBinding(actor: store.actor) {
                    DisclosureGroup("Use a suggestion", isExpanded: $showSuggestion) {
                        ChallengeHealthSuggestionView(flow: health, binding: binding, policy: draft.policy, days: draft.duration ?? 7) {
                            draft.target = draft.metric.inputValue($0)
                        }.buttonStyle(SignalSecondaryButtonStyle()).padding(.top, 12)
                    }.font(.subheadline)
                }
            } else {
                Text(draft.policy.hasTarget ? "Everyone chooses their goal in the lobby." : draft.policy.scoring).font(.subheadline)
            }
        }
    }
    private var goalUnit: String {
        switch draft.metric {
        case .steps: "steps total"
        case .exercise: "minutes : seconds total"
        case .distance: "kilometres total"
        case .timed: "minutes : seconds · finish under this time"
        }
    }
    private var datesStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignalNumberEntry(text: $draft.days, title: "Duration", unit: "full days", id: "beta.create.days", keyboard: .numberPad)
            HStack(spacing: 16) {
                adjust("Fewer days", symbol: "minus", id: "beta.stepper.days-Decrement", disabled: (draft.duration ?? 1) <= 1) { draft.days = String(max(1, (draft.duration ?? 7) - 1)) }
                adjust("More days", symbol: "plus", id: "beta.stepper.days-Increment", disabled: (draft.duration ?? 30) >= 30) { draft.days = String(min(30, (draft.duration ?? 7) + 1)) }
                Spacer()
            }
            DatePicker("Starts", selection: $draft.start, in: draft.allowedDates, displayedComponents: .date)
                .environment(\.timeZone, draft.calendar.timeZone)
                .font(.headline).accessibilityIdentifier("beta.create.start")
            Button { zonePicker = true } label: {
                HStack {
                    Label(SignalTimeZone.name(draft.zone), systemImage: "globe")
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }.buttonStyle(SignalSecondaryButtonStyle()).accessibilityLabel("Time zone, " + SignalTimeZone.name(draft.zone)).accessibilityIdentifier("beta.create.zone")
            if let window = draft.window { SignalDateSpan(window: window) }
            Text("Start in 2–30 days; each day runs midnight to midnight.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        }
    }
    private func adjust(_ title: String, symbol: String, id: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }.accessibilityLabel(title)
            .modifier(SignalCircleAction()).disabled(disabled).accessibilityIdentifier(id)
    }
    private var amountStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignalNumberEntry(text: $draft.dollars, title: "Simulated amount", unit: "USD · $1–$500", id: "beta.create.amount", keyboard: .numberPad, prefix: "$")
            Text("Simulated stakes — no real money moves.").font(.subheadline)
            SignalFactRow(label: "Fee", value: "$0")
            SignalFactRow(label: "Real money", value: "$0")
        }
    }
    @ViewBuilder private var reviewStep: some View {
        if let window = draft.window {
            if draft.mode == .personal, let value = draft.metric.parse(draft.target) { SignalTargetBand(value: value, metric: draft.metric) }
            else { Label(draft.metric.title, systemImage: draft.metric.symbol).font(.title2.weight(.semibold)) }
            if draft.metric == .timed, let distance = window.distanceMm { Text("Whole run: " + ChallengeV1Policy.Metric.distance.display(distance)).font(.headline) }
            SignalDateSpan(window: window)
            SignalFactRow(label: "Simulated amount", value: challengeMoney(window.amountCents) + " · Fee $0")
            Text("Simulated stakes — no real money moves. Nothing can be paid out or redeemed.").font(.subheadline)
            if draft.mode == .personal {
                Text(health == nil ? "Source: fictional activity for this local preview. No Apple Health activity is scored." : ChallengeHealthCopy.source(draft.source?.identifier ?? "")).font(.subheadline)
                Text("Meet your goal and your simulated entry returns. A confirmed miss leaves it unallocated. Missing or unclear activity never proves a miss.").font(.subheadline)
                Text("You can leave before the result is final. You have 48 hours after the result notice to ask for a review.").font(.subheadline)
            } else {
                Text("Choose your friends next. Everyone reviews the roster and rules before agreeing.").font(.subheadline)
            }
            DisclosureGroup(draft.mode == .personal ? "Full goal rules" : "Full challenge rules") {
                ChallengeAgreementText(policy: draft.policy, window: window, minimum: draft.mode == .personal ? 1 : 2, sourcePolicy: health != nil ? draft.source?.identifier : nil)
                    .padding(.top, 12)
            }.font(.headline).accessibilityIdentifier("beta.create.rules")
            if draft.mode == .personal {
                if let health, let binding = draft.healthBinding(actor: store.actor) {
                    ChallengeHealthStatusView(flow: health, binding: binding, readiness: true).buttonStyle(SignalSecondaryButtonStyle())
                }
                Toggle("I have read the complete rules and agree", isOn: $draft.consent)
                    .font(.body).accessibilityIdentifier("beta.personal.consent")
            }
        }
    }
    private var primaryAction: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task {
                if draft.step == .review || store.pending != nil { await draft.submit(store: store) }
                else { await draft.advance(store: store) }
                if let error = draft.error { SignalAccessibility.announce(error) }
            }
        } label: {
            HStack {
                Text(store.pending != nil ? "Retry saved action" : draft.step == .review ? (draft.mode == .personal ? "Create personal goal" : "Create lobby") : draft.step == .amount ? "Review" : "Continue")
                if draft.step != .review { Image(systemName: "arrow.right").accessibilityHidden(true) }
            }.font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .modifier(SignalNativeAction(primary: true))
        .disabled(blocked || (store.pending == nil && draft.step == .review && (store.access?.ageConfirmed != true || draft.mode == .personal && (!draft.consent || !ready))))
        .accessibilityIdentifier(store.pending != nil ? "beta.create.retry" : draft.step == .review ? (draft.mode == .personal ? "beta.personal.commit" : "beta.create.submit") : draft.step == .amount && draft.mode == .personal ? "beta.personal.preview" : "beta.create.continue")
    }
    private func saved(id: UUID, status: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Saved", systemImage: "checkmark.circle").font(.title2).foregroundStyle(SignalTheme.accent)
                Text(draft.savedPolicy?.mode == .personal ? "Your goal is saved." : "Your lobby is ready.").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("beta.create.saved")
                if let row = store.challenges.first(where: { $0.id == id }) {
                    SignalChallengeHeader(row: row, actor: store.actor)
                } else {
                    Text(status == "active" ? "Active" : status == "scheduled" ? "Scheduled" : "Choose your roster").font(.headline)
                    Text("Open the details to load your recorded goal and dates.").font(.subheadline)
                }
                NavigationLink { ChallengeV1Detail(store: store, id: id) } label: {
                    Text(draft.savedPolicy?.mode == .personal ? "View goal" : "View lobby").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }.modifier(SignalNativeAction(primary: true)).accessibilityIdentifier("beta.create.detail")
            }.padding(SignalTheme.contentInset)
        }.background(SignalTheme.canvas).navigationTitle("Saved").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close").modifier(SignalNavigationAction()).accessibilityIdentifier("beta.create.close") }
    }
}
