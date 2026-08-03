import SwiftUI

struct PersonalChallengeDetailView: View {
    let challengeID: UUID

    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingCancelConfirmation = false

    private var challenge: PersonalChallengeDetail? {
        store.detail(for: challengeID)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                TestCommitmentDisclosure()
                if let challenge {
                    hero(challenge)
                    frozenTerms(challenge.terms)
                    progress(challenge)
                    result(challenge)
                    sync(challenge)
                    cancellation(challenge)
                } else {
                    DaybreakCard {
                        ProgressView("Loading personal challenge…")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("Personal challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: challengeID) {
            await store.loadDetail(challengeID: challengeID)
        }
        .confirmationDialog(
            "Cancel before it begins?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel personal challenge", role: .destructive) {
                Task {
                    if await store.cancel(challengeID: challengeID) {
                        dismiss()
                    }
                }
            }
            Button("Keep challenge", role: .cancel) {}
        } message: {
            Text(
                "Cancellation is available only before the frozen start time. No money can be charged in Stage A."
            )
        }
    }

    private func hero(_ challenge: PersonalChallengeDetail) -> some View {
        DaybreakCard(tone: .inverse) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    PersonalStatusPill(
                        status: challenge.presentationStatus(at: Date()),
                        outcome: challenge.outcome?.kind
                    )
                    Spacer(minLength: 8)
                    Text(challenge.terms.commitmentText)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 24,
                                relativeTo: .title2
                            )
                        )
                }
                Text(challenge.terms.targetText)
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 30,
                            relativeTo: .title
                        )
                    )
                    .tracking(-0.8)
                PersonalProgressBar(
                    progress: challenge.progress,
                    terms: challenge.terms
                )
                .colorScheme(.dark)
            }
        }
    }

    private func frozenTerms(_ terms: FrozenPersonalTerms) -> some View {
        Group {
            DaybreakSectionLabel(text: "Frozen terms")
            DaybreakCard {
                VStack(spacing: 0) {
                    termRow("Metric", "Steps only")
                    divider
                    termRow("Cadence", terms.cadence.title)
                    divider
                    termRow("Target", terms.targetText)
                    divider
                    termRow("Commitment", terms.commitmentText)
                    divider
                    termRow("Settlement", "Test only")
                    divider
                    termRow("Timezone", terms.timezone)
                    divider
                    termRow(
                        "Starts",
                        PersonalTermsDateFormatter.dateTime(
                            terms.startsAt,
                            timezoneIdentifier: terms.timezone
                        )
                    )
                    divider
                    termRow(
                        "Ends",
                        PersonalTermsDateFormatter.dateTime(
                            terms.endsAt,
                            timezoneIdentifier: terms.timezone
                        )
                    )
                    divider
                    termRow(
                        "Final sync cutoff",
                        PersonalTermsDateFormatter.dateTime(
                            terms.evidenceCutoff,
                            timezoneIdentifier: terms.timezone
                        )
                    )
                }
            }
        }
    }

    private func progress(_ challenge: PersonalChallengeDetail) -> some View {
        Group {
            DaybreakSectionLabel(text: "Seven-day evidence")
            DaybreakCard {
                if challenge.progress.days.isEmpty {
                    Text("Daily evidence will appear after the challenge starts.")
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                } else {
                    PersonalSevenDayTimeline(days: challenge.progress.days)
                }
            }
            DaybreakCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Evidence completeness", systemImage: "checkmark.shield")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                    Text(
                        "\(challenge.progress.coveredBucketCount.formatted()) of \(challenge.progress.expectedBucketCount.formatted()) completed local-hour intervals covered"
                    )
                    .font(.subheadline)
                    Text(evidenceExplanation(challenge.progress.evidenceState))
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func result(_ challenge: PersonalChallengeDetail) -> some View {
        if let outcome = challenge.outcome {
            DaybreakSectionLabel(text: "Result")
            DaybreakCard(tone: outcome.kind == .metGoal ? .standard : .pledge) {
                VStack(alignment: .leading, spacing: 9) {
                    PersonalStatusPill(
                        status: challenge.presentationStatus(at: Date()),
                        outcome: outcome.kind
                    )
                    Text(resultTitle(outcome.kind))
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 23,
                                relativeTo: .title2
                            )
                        )
                    Text(resultExplanation(outcome))
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    private func sync(_ challenge: PersonalChallengeDetail) -> some View {
        Group {
            DaybreakSectionLabel(text: "Sync health")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 11) {
                    if let date = challenge.progress.lastTrustedSyncAt {
                        Label(
                            "Trusted sync \(date.formatted(.relative(presentation: .named)))",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(CompetitiveTrustTheme.mintInk)
                    } else {
                        Label(
                            "No trusted sync received",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(CompetitiveTrustTheme.sunInk)
                    }
                    if let message = store.syncState(for: challenge.id).message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    Button("Sync steps now") {
                        Task { await store.sync(challengeID: challenge.id) }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(
                        !challenge.permitsActivitySync(at: Date())
                            || !store.configuration.activitySyncEnabled
                            || store.isSyncingActivity
                    )
                    .accessibilityIdentifier("personal.sync")
                    Text(
                        "Final trusted activity can arrive until 24 hours after the seventh local day ends. Missing or unresolved evidence makes the result inconclusive and waives the test commitment."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func cancellation(_ challenge: PersonalChallengeDetail) -> some View {
        if challenge.status == .scheduled {
            Button("Cancel before start", role: .destructive) {
                showingCancelConfirmation = true
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            .disabled(store.isMutating || Date() >= challenge.terms.startsAt)
            .accessibilityIdentifier("personal.cancel")
        }
    }

    private func termRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Divider().overlay(CompetitiveTrustTheme.border)
    }

    private func evidenceExplanation(_ state: PersonalEvidenceState) -> String {
        switch state {
        case .complete:
            "Trusted coverage is complete for the intervals currently expected."
        case .future:
            "Evidence is not expected until the challenge begins."
        case .inProgress, .pending:
            "Coverage is still arriving. The target is not judged before the final cutoff."
        case .outageWaived:
            "A confirmed GameTime outage waives the commitment without an eligibility hold."
        case .incomplete, .missing, .quarantined, .conflicting, .unresolved:
            "Evidence cannot support a goal judgment. The commitment is waived and a diagnostic may be required."
        }
    }

    private func resultTitle(_ kind: PersonalOutcomeKind) -> String {
        switch kind {
        case .metGoal: "You met your goal"
        case .missedGoal: "Goal not met"
        case .inconclusive: "No goal judgment"
        }
    }

    private func resultExplanation(_ outcome: PersonalOutcome) -> String {
        switch outcome.kind {
        case .metGoal:
            "Complete trusted evidence reached the frozen target."
        case .missedGoal:
            "Complete trusted evidence did not reach the frozen target. No money is charged in Stage A."
        case .inconclusive:
            "Evidence was missing, quarantined, conflicting, or unresolved. The commitment is waived. Reason: \(outcome.reasonCode.replacingOccurrences(of: "_", with: " "))."
        }
    }
}
