import SwiftUI

/// Floodlight round 12: the screen before Apple Health's own sheet. It appears
/// once per person, the first time they create or join a challenge. Connect
/// asks for steps, Activity minutes and outdoor runs in one request; Not now
/// goes straight on, and a challenge's Health card covers it from there.
struct ConnectAppleHealthView: View {
    @Bindable var flow: ChallengeHealthFlowStore
    /// Called once, however the person leaves. They carry on to what they
    /// were doing: creating, or agreeing to a challenge.
    let finish: () -> Void

    private enum Step { case ask, connecting, nothingReadable, checking }
    @State private var step = Step.ask

    static let manageAccessURL = URL(string: "https://support.apple.com/en-us/HT204351")!

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero.padding(.horizontal, 18).padding(.top, top + 26).padding(.bottom, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .top) { FloodlightSky() }
                    panel.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 22)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(.container, edges: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .background(Floodlight.ground.ignoresSafeArea())
        .foregroundStyle(Floodlight.ink)
        .tint(Floodlight.accent)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(nothingReadable ? "health.permission.none" : "health.permission")
    }

    private var nothingReadable: Bool { step == .nothingReadable || step == .checking }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: nothingReadable ? "heart.text.clipboard" : "heart.fill")
                .font(.system(size: 38, weight: nothingReadable ? .regular : .medium))
                .foregroundStyle(nothingReadable ? Floodlight.link : Floodlight.brand)
                .frame(width: 84, height: 84).floodlightHero(radius: 24)
                .accessibilityHidden(true)
            FloodlightTitle(nothingReadable ? ChallengeHealthCopy.title(.noEligibleDataYet) : ChallengeHealthCopy.title(.notConnected),
                            size: 38, maxScale: 1.4, spacing: -0.01)
                .foregroundStyle(Floodlight.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).padding(.top, 18)
            Text(nothingReadable ? ChallengeHealthCopy.explanation(.noEligibleDataYet, timed: false) : Self.readOnlyLine)
                .floodlightFont(15.5, weight: .medium).foregroundStyle(Floodlight.heroMuted).lineSpacing(2)
                .frame(maxWidth: 320, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
    }

    // MARK: Panel

    @ViewBuilder private var panel: some View {
        if nothingReadable {
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.missingLine).floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await recheck() }
                } label: {
                    if step == .checking {
                        HStack(spacing: 8) { ProgressView(); Text(ChallengeHealthCopy.title(.checking)) }
                    } else {
                        Text("Refresh activity check")
                    }
                }
                .buttonStyle(FloodlightCalmButtonStyle()).disabled(step == .checking)
                .accessibilityIdentifier("health.permission.refresh")
                Link("Manage access in Apple Health", destination: Self.manageAccessURL)
                    .floodlightFont(13.5, weight: .semibold).foregroundStyle(Floodlight.link).frame(minHeight: 44)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).floodlightCard(radius: 20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                FloodlightLabel("What we read").padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                rows([("figure.walk", "Steps"), ("stopwatch", "Activity minutes"), ("figure.run", "Outdoor runs")], weight: .semibold)
                rows([("pencil.slash", Self.neverWriteLine), ("person.2", Self.friendsLine)], weight: .medium)
            }
        }
    }

    private func rows(_ items: [(symbol: String, text: String)], weight: Font.Weight) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(Floodlight.line).frame(height: 1).padding(.leading, 60) }
                HStack(spacing: 12) {
                    Image(systemName: item.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Floodlight.link)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Floodlight.well))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text(item.text).floodlightFont(15, weight: weight).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 54)
            }
        }
        .floodlightCard(radius: 20)
    }

    // MARK: Footer

    private var foot: some View {
        VStack(spacing: 4) {
            Text(Self.browsingLine).floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
            if nothingReadable {
                Button("Continue", action: finish).buttonStyle(FloodlightPrimaryButtonStyle())
                    .accessibilityIdentifier("health.permission.continue")
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    if step == .connecting { ProgressView().tint(Floodlight.buttonInk) } else { Text("Connect") }
                }
                .buttonStyle(FloodlightPrimaryButtonStyle()).disabled(step == .connecting)
                .accessibilityLabel("Connect Apple Health").accessibilityIdentifier("health.permission.connect")
                Button("Not now") {
                    flow.dismissAppleHealthIntroduction()
                    finish()
                }
                .buttonStyle(FloodlightQuietButtonStyle()).disabled(step == .connecting)
                .accessibilityIdentifier("health.permission.not-now")
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Floodlight.ground.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Floodlight.line).frame(height: 1) }
    }

    // MARK: Actions

    private func connect() async {
        step = .connecting
        guard await flow.connectAppleHealth() else { step = .ask; return }
        if await flow.hasRecentAppleHealthActivity() {
            finish()
        } else {
            step = .nothingReadable
            SignalAccessibility.announce(ChallengeHealthCopy.title(.noEligibleDataYet))
        }
    }

    private func recheck() async {
        step = .checking
        if await flow.hasRecentAppleHealthActivity() { finish() } else { step = .nothingReadable }
    }

    // COPY.md "Sign in and Health permission".
    static let readOnlyLine = "We read only what we need to check your challenge progress."
    static let neverWriteLine = "We never write to Apple Health."
    static let friendsLine = "Friends see your progress, not your workouts."
    static let browsingLine = "You can keep browsing without it."
    static let missingLine = "Missing activity doesn’t count against you."
}

/// Shows Connect Apple Health first when this person hasn't seen it yet, then
/// the flow they started. The decision is made once, when the flow opens.
struct AppleHealthIntroductionGate<Content: View>: View {
    @Environment(\.challengeHealthFlow) private var flow
    @ViewBuilder let content: () -> Content
    @State private var showing: Bool?

    var body: some View {
        Group {
            if showing == true, let flow {
                ConnectAppleHealthView(flow: flow) { showing = false }
                    .transition(.opacity)
            } else if showing == false {
                content()
            } else {
                Floodlight.ground.ignoresSafeArea()
            }
        }
        .onAppear { if showing == nil { showing = flow?.needsAppleHealthIntroduction ?? false } }
    }
}
