import SwiftUI

// Shared Glass Arena pieces: avatars, pills, cards, rows, the segmented control
// and the chrome tab bar.

// MARK: - Layout

enum GlassArenaLayout {
    static let screenPadding: CGFloat = 20
    static let detailPadding: CGFloat = 18
    static let cardGap: CGFloat = 15

    static let tabBarHeight: CGFloat = 62
    static let tabBarSideInset: CGFloat = 16
    static let tabBarBottomPadding: CGFloat = 8

    /// How far the final card in a list slides beneath the translucent bar, so
    /// real content passes under it.
    static let underBarOverlap: CGFloat = 24

    /// Bottom padding for scrolling content that sits behind the tab bar.
    static var scrollBottomInset: CGFloat {
        tabBarHeight + tabBarBottomPadding - underBarOverlap
    }
}

// MARK: - Avatar

/// Initials on a tinted circle. Teal is you, violet is your opponent.
struct GlassAvatar: View {
    enum Side {
        case you
        case them
        case neutral

        var accent: Color {
            switch self {
            case .you: GlassArena.teal700
            case .them: GlassArena.violet500
            case .neutral: GlassArena.mutedLight
            }
        }

        var text: Color {
            switch self {
            case .you: GlassArena.teal900
            case .them: GlassArena.violet800
            case .neutral: GlassArena.inkSecondary
            }
        }
    }

    let initials: String
    var size: CGFloat = 42
    var side: Side = .you
    var ringWidth: CGFloat = 0
    var showsGlow = false
    /// The Result screen's loser: ring at 45% and muted text.
    var isDesaturated = false

    private var fontSize: CGFloat {
        size * (initials.count > 1 ? 0.34 : 0.38)
    }

    var body: some View {
        Text(initials)
            .font(GlassArenaFont.display(fontSize, .heavy))
            .foregroundStyle(
                isDesaturated
                    ? Color(glassArenaHex: 0x6B5DA0)
                    : side.text
            )
            .frame(width: size, height: size)
            .background {
                Circle().fill(
                    LinearGradient(
                        colors: [
                            side.accent.opacity(isDesaturated ? 0.14 : 0.28),
                            side.accent.opacity(isDesaturated ? 0.08 : 0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                Circle().strokeBorder(
                    ringWidth > 0
                        ? side.accent.opacity(isDesaturated ? 0.45 : 1)
                        : .white.opacity(0.9),
                    lineWidth: ringWidth > 0 ? ringWidth : 1
                )
            }
            .shadow(
                color: showsGlow
                    ? side.accent.opacity(0.45)
                    : .clear,
                radius: 10,
                y: 8
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Pills and eyebrows

/// The amber stake and countdown pills. Time pressure is always visible.
struct AmberPill: View {
    var systemImage: String?
    let text: String
    var fontSize: CGFloat = 13
    var isDisplayFont = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize - 1, weight: .bold))
            }
            Text(text)
                .font(
                    isDisplayFont
                        ? GlassArenaFont.display(fontSize, .heavy)
                        : GlassArenaFont.text(fontSize, .bold)
                )
        }
        .foregroundStyle(GlassArena.amber800)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(GlassArena.amber400.opacity(0.20))
        )
        .accessibilityElement(children: .combine)
    }
}

/// "⚡ WEEKEND DISTANCE" — the duel's identity line.
struct DuelEyebrow: View {
    let text: String
    var fontSize: CGFloat = 13
    var tracking: CGFloat = 0.5
    var isChip = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill")
                .font(.system(size: fontSize + 1, weight: .bold))
            Text(text.uppercased())
                .font(GlassArenaFont.text(fontSize, .bold))
                .tracking(tracking)
        }
        .foregroundStyle(GlassArena.teal900)
        .padding(.horizontal, isChip ? 14 : 0)
        .padding(.vertical, isChip ? 6 : 0)
        .background {
            if isChip {
                Capsule()
                    .fill(GlassArena.teal700.opacity(0.16))
                    .overlay {
                        Capsule().strokeBorder(
                            GlassArena.teal700.opacity(0.32),
                            lineWidth: 1
                        )
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A muted uppercase section label — "WAITING ON YOU", "ROPE MOVED".
struct SectionEyebrow: View {
    let text: String
    var fontSize: CGFloat = 12
    var tracking: CGFloat = 1.1

    var body: some View {
        Text(text.uppercased())
            .font(GlassArenaFont.text(fontSize, .bold))
            .tracking(tracking)
            .foregroundStyle(GlassArena.mutedLight)
    }
}

/// A small teal action chip — "Add".
struct TealChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(GlassArenaFont.text(14, .bold))
            .foregroundStyle(GlassArena.teal900)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GlassArena.teal700.opacity(0.15))
            )
    }
}

// MARK: - Screen chrome

/// Today's and Duels' large title.
struct GlassScreenTitle: View {
    let eyebrow: String?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(GlassArenaFont.text(13, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(GlassArena.mutedLight)
            }
            Text(title)
                .font(GlassArenaFont.display(33, .heavy))
                .foregroundStyle(GlassArena.ink)
                .lineSpacing(2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The pushed-screen nav row: a teal back affordance and a trailing pill.
struct GlassNavRow<Trailing: View>: View {
    let backTitle: String
    let back: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                    Text(backTitle)
                        .font(GlassArenaFont.text(16, .semibold))
                }
                .foregroundStyle(GlassArena.teal800)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nav.back")
            .accessibilityLabel("Back to \(backTitle)")

            Spacer()
            trailing()
        }
        .padding(.horizontal, GlassArenaLayout.screenPadding)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Stat card

/// "HIS BEST / 4.0 km Fri" — one stat about them, one about you.
struct GlassStatCard: View {
    let systemImage: String
    let label: String
    let value: String
    let qualifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(label.uppercased())
                    .font(GlassArenaFont.text(11, .bold))
                    .tracking(0.6)
            }
            .foregroundStyle(GlassArena.mutedLight)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(GlassArenaFont.display(22, .heavy))
                    .foregroundStyle(GlassArena.ink)
                if let qualifier {
                    Text(qualifier)
                        .font(GlassArenaFont.text(13, .semibold))
                        .foregroundStyle(GlassArena.mutedLight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .glassPane(.standard, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Timeline

/// "Rope moved" — who gained ground, and when.
struct RopeTimeline: View {
    let events: [RopeEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Rope moved", fontSize: 11, tracking: 0.9)
            ForEach(events) { event in
                row(event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .glassPane(.standard, cornerRadius: 28)
    }

    private func row(_ event: RopeEvent) -> some View {
        HStack(spacing: 11) {
            Image(systemName: glyph(event.direction))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(glyphColor(event.direction))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(glyphColor(event.direction).opacity(0.16))
                )

            Group {
                if let actor = event.actor {
                    Text(actor)
                        .font(GlassArenaFont.text(14, .bold))
                        .foregroundStyle(GlassArena.ink)
                        + Text(" \(event.detail)")
                        .font(GlassArenaFont.text(14))
                        .foregroundStyle(GlassArena.inkSecondary)
                } else {
                    Text(event.detail)
                        .font(GlassArenaFont.text(14))
                        .foregroundStyle(GlassArena.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(event.age)
                .font(GlassArenaFont.text(12))
                .foregroundStyle(GlassArena.mutedLightest)
        }
        .accessibilityElement(children: .combine)
    }

    private func glyph(_ direction: RopeEvent.Direction) -> String {
        switch direction {
        case .theyPulled: "arrow.left"
        case .youPulled: "arrow.right"
        case .opened: "plus"
        }
    }

    private func glyphColor(_ direction: RopeEvent.Direction) -> Color {
        switch direction {
        case .theyPulled: GlassArena.violet600
        case .youPulled: GlassArena.teal800
        case .opened: GlassArena.amber700
        }
    }
}

// MARK: - Rows

/// An incoming duel — amber-outlined, because it is waiting on you.
struct InviteCard: View {
    let initials: String
    let title: String
    let terms: String
    let acceptTitle: String
    var cornerRadius: CGFloat = 28
    var isBusy = false
    var isEnabled = true
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                GlassAvatar(initials: initials, size: 40, side: .them)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(GlassArenaFont.text(16, .bold))
                        .foregroundStyle(GlassArena.ink)
                    Text(terms)
                        .font(GlassArenaFont.text(13))
                        .foregroundStyle(GlassArena.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Button(action: accept) {
                    if isBusy {
                        ProgressView()
                            .tint(GlassArena.tealInk)
                    } else {
                        Label(acceptTitle, systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 44,
                        cornerRadius: 16,
                        fontSize: 15
                    )
                )
                .disabled(!isEnabled || isBusy)
                .accessibilityIdentifier("invite.accept")

                Button("Nope", action: decline)
                    .buttonStyle(GlassQuietButtonStyle())
                    .frame(width: 96)
                    .disabled(!isEnabled || isBusy)
                    .accessibilityIdentifier("invite.decline")
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .glassPane(
            .standard,
            cornerRadius: cornerRadius,
            borderColor: GlassArena.amber400.opacity(0.44)
        )
    }
}

/// A pending friend request — "Jordan Lee wants in".
struct FriendRequestRow: View {
    let displayName: String
    let handle: String
    var actionTitle: String?
    var isEnabled = true
    var action: (() -> Void)?
    var tap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GlassArena.teal800)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(GlassArena.teal700.opacity(0.16))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(displayName) wants in")
                    .font(GlassArenaFont.text(15, .bold))
                    .foregroundStyle(GlassArena.ink)
                Text("@\(handle)")
                    .font(GlassArenaFont.text(13))
                    .foregroundStyle(GlassArena.mutedLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(action: action) {
                    TealChip(text: actionTitle)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel("\(actionTitle) \(displayName)")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .glassPane(.standard, cornerRadius: 26)
        .contentShape(Rectangle())
        .onTapGesture { tap?() }
    }
}

/// A settled duel. Recessed glass — it reads as inactive.
struct CompletedDuelRow: View {
    /// Today marks a win in amber; the Duels list marks it in teal.
    enum WinTint {
        case amber
        case teal

        var color: Color {
            switch self {
            case .amber: GlassArena.amber700
            case .teal: GlassArena.teal800
            }
        }
    }

    let title: String
    let outcome: String
    /// Nil while the result is unknown.
    let didWin: Bool?
    var winTint: WinTint = .amber
    var showsChevron = false
    /// The final row in a list slides under the tab bar.
    var slidesUnderTabBar = false

    private var glyph: String {
        switch didWin {
        case true: "checkmark.seal"
        case false: "minus.circle"
        case nil: "clock.badge.questionmark"
        }
    }

    private var tint: Color {
        switch didWin {
        case true: winTint.color
        case false: GlassArena.mutedLighter
        case nil: GlassArena.mutedLightest
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(tint.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(GlassArenaFont.text(15, .bold))
                    .foregroundStyle(GlassArena.ink)
                Text(outcome)
                    .font(GlassArenaFont.text(13))
                    .foregroundStyle(GlassArena.mutedLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GlassArena.hairline)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(
            .bottom,
            slidesUnderTabBar
                ? 14 + GlassArenaLayout.underBarOverlap
                : 14
        )
        .glassPane(
            .recessed,
            cornerRadius: 26,
            topCornersOnly: slidesUnderTabBar
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inline states

/// Health sync failure never blocks: an inline amber row inside the affected
/// card, and a stale duel still shows its last known rope.
struct StaleHealthRow: View {
    let lastSyncedAt: Date
    var now = Date()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
            Text(
                "Can't reach Apple Health — last synced \(DuelClock.syncAge(from: lastSyncedAt, now: now))"
            )
            .font(GlassArenaFont.text(12, .semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GlassArena.amber800)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(GlassArena.amber400.opacity(0.18))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Loading renders the pane's real structure with values as shimmering blocks —
/// never a spinner over an empty screen.
struct ShimmerBlock: View {
    var width: CGFloat?
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(GlassArena.ink.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.65),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: 0.4, anchor: .leading)
                    .offset(x: phase * (width ?? 200))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                    )
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: 1.3).repeatForever(autoreverses: false)
                ) {
                    phase = 1.6
                }
            }
            .accessibilityHidden(true)
    }
}

/// "Nobody's challenged you." — hero glass, with the primary action inside it.
struct EmptyDuelsCard: View {
    let title: String
    let message: String
    var actionTitle: String?
    var isEnabled = true
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(GlassArenaFont.display(24, .heavy))
                .foregroundStyle(GlassArena.ink)
            Text(message)
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 50,
                        cornerRadius: 18,
                        fontSize: 16
                    )
                )
                .disabled(!isEnabled)
                .accessibilityIdentifier("duels.empty-create")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassPane(.hero, cornerRadius: 30)
        .accessibilityIdentifier("state.empty")
    }
}

/// The offline retry, kept inline rather than blocking the screen.
struct GlassRetryRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .bold))
                Text("Couldn't refresh")
                    .font(GlassArenaFont.text(15, .bold))
            }
            .foregroundStyle(GlassArena.ink)

            Text(message)
                .font(GlassArenaFont.text(13))
                .foregroundStyle(GlassArena.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again", action: retry)
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 44,
                        cornerRadius: 16,
                        fontSize: 15
                    )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPane(.standard, cornerRadius: 28)
        .accessibilityIdentifier("state.offline")
    }
}

// MARK: - Segmented control

struct GlassSegmentedControl<Segment: Hashable>: View {
    struct Item: Identifiable {
        let segment: Segment
        let title: String
        /// A solid amber count — Invites carries one when something waits.
        var badge: Int?

        var id: String { title }
    }

    let items: [Item]
    @Binding var selection: Segment

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = item.segment
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(
                                GlassArenaFont.text(
                                    14,
                                    selection == item.segment ? .bold : .semibold
                                )
                            )
                            .foregroundStyle(
                                selection == item.segment
                                    ? GlassArena.ink
                                    : GlassArena.mutedLight
                            )
                        if let badge = item.badge, badge > 0 {
                            Text("\(badge)")
                                .font(GlassArenaFont.display(11, .heavy))
                                .foregroundStyle(GlassArena.amberInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(GlassArena.amber400)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if selection == item.segment {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .fill(.white)
                            .shadow(
                                color: Color(
                                    glassArenaHex: 0x142834,
                                    opacity: 0.28
                                ),
                                radius: 5,
                                y: 3
                            )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "segment.\(item.title.lowercased())"
                )
                .accessibilityAddTraits(
                    selection == item.segment ? [.isSelected] : []
                )
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.white.opacity(0.45))
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(.white.opacity(0.68), lineWidth: 1)
                }
        }
    }
}

// MARK: - Tab bar

/// The chrome tier: heaviest blur, bright top and bottom edges, an upward glow
/// plus a downward drop. Content passes beneath it.
struct GlassTabBar: View {
    @Binding var selection: AppTab

    private struct Item {
        let tab: AppTab
        let title: String
        let filled: String
        let outline: String
        let identifier: String
    }

    private let items: [Item] = [
        Item(
            tab: .today,
            title: "Today",
            filled: "house.fill",
            outline: "house",
            identifier: "tab.today"
        ),
        Item(
            tab: .duels,
            title: "Duels",
            filled: "bolt.fill",
            outline: "bolt",
            identifier: "tab.duels"
        ),
        Item(
            tab: .friends,
            title: "Friends",
            filled: "person.2.fill",
            outline: "person.2",
            identifier: "tab.friends"
        ),
        Item(
            tab: .you,
            title: "You",
            filled: "person.crop.circle.fill",
            outline: "person.crop.circle",
            identifier: "tab.you"
        ),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.identifier) { item in
                let isActive = selection == item.tab
                Button {
                    selection = item.tab
                } label: {
                    VStack(spacing: 4) {
                        Image(
                            systemName: isActive ? item.filled : item.outline
                        )
                        .font(
                            .system(
                                size: 21,
                                weight: isActive ? .semibold : .medium
                            )
                        )
                        .foregroundStyle(
                            isActive
                                ? GlassArena.teal800
                                : GlassArena.mutedGlyph
                        )
                        .frame(height: 23)

                        Text(item.title)
                            .font(
                                GlassArenaFont.text(
                                    10.5,
                                    isActive ? .bold : .semibold
                                )
                            )
                            .foregroundStyle(
                                isActive
                                    ? GlassArena.teal900
                                    : GlassArena.mutedLight
                            )
                    }
                    .frame(width: 66)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.identifier)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: GlassArenaLayout.tabBarHeight)
        .glassPane(.chrome, cornerRadius: 28)
    }
}
