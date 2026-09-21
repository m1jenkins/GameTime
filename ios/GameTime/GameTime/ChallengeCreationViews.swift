import SwiftUI
import GameTimeCore

struct ChallengeV1Create: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.challengeHealthFlow) private var health
    @State private var draft: ChallengeCreationDraft
    private enum Editor: String, Identifiable { case dates, amount; var id: String { rawValue } }
    @State private var editor: Editor?
    @State private var focusedInput: String?
    @State private var keyboardVisible = false
    @ScaledMetric(relativeTo: .title3) private var choiceSymbolWidth: CGFloat = 28
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
        case .activity: draft.mode == .personal ? "What’s your goal?" : "Choose your activity."
        case .review: draft.mode == .personal ? "Review your goal." : "Make it a challenge."
        }
    }
    private var ready: Bool { health == nil || draft.healthBinding(actor: store.actor).map { health?.canConsent($0) == true } == true }
    private var blocked: Bool { store.busy || draft.reading || !draft.initialized || (store.pending == nil && draft.unavailable) }
    var body: some View {
        NavigationStack {
            if let receipt = draft.receipt, let id = receipt.id {
                if draft.savedPolicy?.mode == .friend {
                    ChallengeCreationInviteView(store: store, challengeID: id, progressLabels: progressLabels)
                } else {
                    saved(id: id, status: receipt.status ?? "scheduled")
                }
            } else {
                flow
            }
        }
        .tint(SignalCreationTheme.accent)
        .onChange(of: store.actor) { draft.close(); dismiss() }
        .onDisappear { draft.close() }
        .task { await draft.initialize(store: store, health: health) }
    }
    private var flow: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    progress.id("creation-top")
                    Text(heading).font(.largeTitle.weight(.bold)).tracking(-0.8)
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
                .padding(SignalCreationTheme.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SignalCreationTheme.canvas)
            .foregroundStyle(SignalCreationTheme.textPrimary)
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
                    SignalAmountEditor(value: draft.dollars) { amount in
                        guard amount != draft.dollars else { return }
                        draft.dollars = amount
                        Task { await draft.review(store: store) }
                    }
                }
            }
        }
    }
    private var progress: some View {
        SignalCreationProgress(labels: progressLabels, current: draft.progress - 1)
            .accessibilityIdentifier("beta.create.progress")
    }
    private var progressLabels: [String] {
        let stages = draft.mode == .personal ? ["Goal", "Rules"] : ["Goal", "Challenge", "Friends"]
        return draft.directEntry ? stages : ["Type"] + stages
    }
    private var typeStep: some View {
        VStack(spacing: 12) {
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
                    Text(detail).font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? SignalCreationTheme.accent : SignalCreationTheme.textSecondary).accessibilityHidden(true)
            }.foregroundStyle(SignalCreationTheme.textPrimary).padding(20)
                .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(selected ? SignalCreationTheme.accent : .clear, lineWidth: 1.5) }
                .contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("beta.create.type." + id)
    }
    @ViewBuilder private var activityStep: some View {
        if !draft.personalStepsOnly { SignalActivityChoices(selection: $draft.metric) }
        if draft.unavailable {
            Text("Activity not available yet. Choose another activity to continue.").font(.subheadline)
        } else {
            if draft.metric == .timed {
                SignalNumberEntry(text: $draft.distance, title: "Whole run", unit: "kilometres", id: "beta.create.distance", keyboard: .decimalPad,
                                  focusChanged: { inputFocus($0, id: "beta.create.distance") })
            }
            if draft.mode == .personal {
                SignalNumberEntry(text: $draft.target, title: draft.metric == .timed ? "Time to beat" : "Your goal", unit: goalUnit,
                                  id: "beta.create.target", keyboard: draft.metric == .steps ? .numberPad : draft.metric == .distance ? .decimalPad : .numbersAndPunctuation,
                                  focusChanged: { inputFocus($0, id: "beta.create.target") })
                if let health, let binding = draft.planningBinding(actor: store.actor) {
                    ChallengeHealthSuggestionView(flow: health, binding: binding, policy: draft.policy, days: draft.duration ?? 7) {
                        draft.target = draft.metric.inputValue($0)
                    }.buttonStyle(SignalSecondaryButtonStyle())
                }
            } else {
                Text(draft.policy.hasTarget ? "Everyone chooses their goal in the lobby." : draft.policy.scoring).font(.subheadline)
            }
        }
        datesSummary
    }
    private func inputFocus(_ focused: Bool, id: String) {
        if focused { focusedInput = id }
        else if focusedInput == id { focusedInput = nil }
    }
    private var goalUnit: String {
        let period = draft.duration.map { $0 == 1 ? "over 1 full day" : "over \($0) full days" } ?? "during your selected dates"
        return switch draft.metric {
        case .steps: "steps total · " + period
        case .exercise: "minutes : seconds total · " + period
        case .distance: "kilometres total · " + period
        case .timed: "minutes : seconds · finish under this time"
        }
    }
    private var datesSummary: some View {
        Button { editor = .dates } label: {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "calendar").font(.title3).padding(.top, 3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.duration.map { $0 == 1 ? "1 full day" : "\($0) full days" } ?? "Choose your dates").font(.headline)
                    Text(dateRange).font(.subheadline)
                    Text(SignalTimeZone.name(draft.zone)).font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("Edit").font(.subheadline.weight(.semibold)).foregroundStyle(SignalCreationTheme.accent)
            }.foregroundStyle(SignalCreationTheme.textPrimary).multilineTextAlignment(.leading)
                .padding(20).background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityIdentifier("beta.create.dates")
            .accessibilityHint("Edit the start date, duration and time zone")
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
        if let window = draft.window {
            VStack(alignment: .leading, spacing: 12) {
                if draft.mode == .personal, let value = draft.metric.parse(draft.target) { SignalCreationMetric(value: value, metric: draft.metric) }
                else {
                    Label(draft.metric.title, systemImage: draft.metric.symbol).font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 24))
                }
                Button("Edit goal and dates") { draft.back() }.font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain).foregroundStyle(SignalCreationTheme.accent).frame(minHeight: 44)
                    .accessibilityIdentifier("beta.create.edit-goal")
            }
            if draft.metric == .timed, let distance = window.distanceMm {
                if health != nil {
                    reviewFact("Whole run distance", text: "\(ChallengeTimedDistanceCopy.range(distance)), including both distances. The whole run must fit inside these dates.")
                } else {
                    Text("Whole run: " + ChallengeV1Policy.Metric.distance.display(distance)).font(.headline)
                }
            }
            SignalDateSpan(window: window)
            if draft.mode == .friend {
                SignalCreationFact(symbol: "lock", title: "Private challenge", detail: "Only people you select can join. Everyone reviews the roster and rules before agreeing.")
            }
            VStack(alignment: .leading, spacing: 12) {
                Button { editor = .amount } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "dollarsign").font(.title3.weight(.medium)).frame(width: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Simulated amount").font(.headline)
                            Text(challengeMoney(window.amountCents) + " · Fee $0").font(.subheadline).monospacedDigit().foregroundStyle(SignalCreationTheme.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text("Edit").font(.subheadline.weight(.semibold)).foregroundStyle(SignalCreationTheme.accent)
                    }.foregroundStyle(SignalCreationTheme.textPrimary).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("beta.create.edit-amount")
                Text("Fee $0 · No real money moves. Nothing can be paid out or redeemed.").font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
            }.padding(20).background(SignalCreationTheme.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            if draft.mode == .personal {
                reviewFact("Activity counted", text: health == nil ? "Fictional activity for this local preview. No Apple Health activity is scored." : ChallengeHealthCopy.source(draft.source?.identifier ?? ""))
                reviewFact("Possible results", text: "Meet your goal and your simulated entry returns. A confirmed miss leaves it unallocated. Missing or unclear activity never proves a miss.")
                reviewFact("Leaving and review", text: "You can leave before the result is final. You have 48 hours after the result notice to ask for a review.")
            } else {
                SignalCreationFact(symbol: "applewatch", title: "Activity counted", detail: health == nil ? "Fictional activity for this local preview. No Apple Health activity is scored." : ChallengeHealthCopy.source(draft.source?.identifier ?? ""))
                SignalCreationFact(symbol: "checkmark.shield", title: "Possible results", detail: draft.policy.allocation)
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
                if draft.needsReview {
                    Text("Your goal changed. Refresh the review before you agree.").font(.subheadline)
                }
                Toggle("I have read the complete rules and agree", isOn: $draft.consent)
                    .disabled(draft.needsReview || draft.reading)
                    .font(.body).accessibilityIdentifier("beta.personal.consent")
            }
        }
    }
    private func reviewFact(_ title: String, text: String) -> some View {
        SignalCreationFact(symbol: title == "Activity counted" ? "applewatch" : title == "Whole run distance" ? "figure.run" : "checkmark.shield", title: title, detail: text)
    }
    private var isReviewAction: Bool { draft.step == .activity || draft.step == .review && draft.needsReview }
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
                Text(store.pending != nil ? "Retry saved action" : isReviewAction ? (draft.step == .review ? "Refresh review" : "Review") : draft.step == .review ? (draft.mode == .personal ? "Create personal goal" : "Create lobby") : "Continue")
                if draft.step != .review { Image(systemName: "arrow.right").accessibilityHidden(true) }
            }.font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(SignalCreationPrimaryStyle())
        .disabled(blocked || (store.pending == nil && draft.step == .review && !draft.needsReview && (store.access?.ageConfirmed != true || draft.mode == .personal && (!draft.consent || !ready))))
        .accessibilityIdentifier(store.pending != nil ? "beta.create.retry" : isReviewAction && draft.mode == .personal ? "beta.personal.preview" : draft.step == .review ? (draft.mode == .personal ? "beta.personal.commit" : "beta.create.submit") : "beta.create.continue")
    }
    private func saved(id: UUID, status: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Saved", systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(SignalCreationTheme.accent)
                Text(draft.savedPolicy?.mode == .personal ? "Your goal is saved." : "Your lobby is ready.").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("beta.create.saved")
                if let row = store.challenges.first(where: { $0.id == id }), store.isFresh(row) {
                    Text(row.title).font(.title2.weight(.semibold))
                    Text(row.statusText).font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                    if let target = row.own(store.actor)?.target {
                        SignalCreationMetric(value: target, metric: row.format.metric)
                    }
                    SignalDateSpan(window: row.config)
                    SignalCreationFact(symbol: "dollarsign", title: "Simulated entry", detail: challengeMoney(row.config.amountCents) + " · No real money moves.")
                } else {
                    Text(status == "active" ? "Active" : status == "scheduled" ? "Scheduled" : "Choose your roster").font(.headline)
                    Text("Open the details to load your recorded goal and dates.").font(.subheadline)
                }
                NavigationLink { ChallengeV1Detail(store: store, id: id) } label: {
                    Text(draft.savedPolicy?.mode == .personal ? "View goal" : "View lobby").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }.buttonStyle(SignalCreationPrimaryStyle()).accessibilityIdentifier("beta.create.detail")
            }.padding(SignalCreationTheme.contentInset)
        }.background(SignalCreationTheme.canvas).navigationTitle("Saved").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close").modifier(SignalNavigationAction()).accessibilityIdentifier("beta.create.close") }
    }
}
