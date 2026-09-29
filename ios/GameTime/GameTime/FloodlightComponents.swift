import SwiftUI

// MARK: - Buttons

/// A screen's one blue action: a flat pill.
struct FloodlightPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.floodlightFont(15, weight: .bold).tracking(0.15)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: height).padding(.horizontal, 18)
            .foregroundStyle(Floodlight.buttonInk)
            .background {
                Capsule().fill(Floodlight.button)
                    .shadow(color: scheme == .dark ? .black.opacity(0.5) : Color(red: 10 / 255, green: 90 / 255, blue: 170 / 255).opacity(0.3),
                            radius: 4, x: 0, y: 3)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A neutral gray pill for Apple Health and other ways through, so each
/// screen keeps one blue action.
struct FloodlightCalmButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var enabled
    @Environment(\.dynamicTypeSize) private var typeSize
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.floodlightFont(15.5, weight: .bold)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: height).padding(.horizontal, 16)
            .foregroundStyle(enabled ? Floodlight.ink : Floodlight.muted)
            .background(Capsule().fill(Floodlight.well))
            .overlay(Capsule().strokeBorder(Floodlight.wellEdge, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

/// A text-only way out, such as Decline.
struct FloodlightQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.floodlightFont(14, weight: .semibold)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Floodlight.muted)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// A quiet card that opens more, such as Full rules.
struct FloodlightRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label.floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Floodlight.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 52)
        .floodlightCard()
        .opacity(configuration.isPressed ? 0.82 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// The round back button on a card fill.
struct FloodlightNavButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Floodlight.ink)
                .frame(width: 40, height: 40)
                .background {
                    Circle().fill(Floodlight.card)
                        .shadow(color: scheme == .dark ? .black.opacity(0.35) : Color(red: 18 / 255, green: 72 / 255, blue: 120 / 255).opacity(0.12),
                                radius: 6, x: 0, y: 4)
                }
                .overlay(Circle().strokeBorder(Floodlight.cardEdge, lineWidth: 1))
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// A small glass status pill, such as "Not started".
struct FloodlightPill: View {
    let text: String
    var body: some View {
        Text(text.uppercased(with: .current)).floodlightFont(11, weight: .semibold).tracking(0.66).accessibilityLabel(text)
            .foregroundStyle(Floodlight.muted)
            .padding(.horizontal, 11).frame(minHeight: 28)
            .background(Capsule().fill(Floodlight.glass))
            .overlay(Capsule().strokeBorder(Floodlight.glassEdge, lineWidth: 1))
    }
}

// MARK: - People

/// A person as a flat circle in their roster color, with their initials.
/// Someone with no saved update gets a dashed outline instead.
struct FloodlightOrb: View {
    enum Badge { case none, met, late }
    let slot: Int
    let initials: String
    var size: CGFloat = 40
    var waiting = false
    var badge: Badge = .none
    var selected = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let member = FloodlightToken.member(slot).rgba(scheme)
        let ink = waiting ? FloodlightToken.muted.rgba(scheme) : FloodlightMaterial.initialsInk(member, scheme)
        ZStack {
            if waiting {
                Circle().strokeBorder(Floodlight.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            } else {
                Circle().fill(member.color)
                    .shadow(color: FloodlightMaterial.value(FloodlightMaterial.drop, scheme).opacity(0.55).color, radius: 3, x: 0, y: 3)
            }
            // Initials are part of the picture: the enclosing control carries the
            // person's name for VoiceOver, and their ink is tested at 4.5:1.
            Canvas { context, canvas in
                var font = size * 0.32
                var text = context.resolve(Text(initials).font(.custom(FloodlightFonts.face(.bold, condensed: false), fixedSize: font))
                    .tracking(-font * 0.02).foregroundColor(ink.color))
                let width = text.measure(in: canvas).width
                if width > canvas.width * 0.78 {
                    font *= canvas.width * 0.78 / width
                    text = context.resolve(Text(initials).font(.custom(FloodlightFonts.face(.bold, condensed: false), fixedSize: font))
                        .foregroundColor(ink.color))
                }
                context.draw(text, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2), anchor: .center)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if selected { Circle().stroke(waiting ? Floodlight.muted : member.color, lineWidth: 2).padding(-5) }
        }
        .overlay(alignment: .bottomTrailing) {
            if badge != .none {
                Image(systemName: badge == .met ? "checkmark" : "clock")
                    .font(.system(size: size > 30 ? 9 : 7, weight: .heavy)).foregroundStyle(Color(red: 11 / 255, green: 20 / 255, blue: 24 / 255))
                    .frame(width: size > 30 ? 17 : 13, height: size > 30 ? 17 : 13)
                    .background(Circle().fill(.white).shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1))
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }

    /// Two letters, the way the rest of the app writes them.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "." })
        return words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            : String(name.prefix(2)).uppercased()
    }
}

/// Overlapping people, left to right in roster order.
struct FloodlightFaceStack: View {
    let people: [(slot: Int, initials: String, badge: FloodlightOrb.Badge, waiting: Bool)]
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                FloodlightOrb(slot: person.slot, initials: person.initials, size: size, waiting: person.waiting, badge: person.badge)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// A challenge's days as pips: past, today, then the days still to come.
struct FloodlightWeekPips: View {
    let days: Int
    let today: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<days, id: \.self) { day in
                Capsule()
                    .fill(day < today ? FloodlightMaterial.color(FloodlightMaterial.pipPast)
                          : day == today ? Floodlight.accent : Floodlight.groove)
                    .frame(width: 16, height: 6)
                    .shadow(color: day == today ? Floodlight.accent.opacity(0.45) : .clear, radius: 3)
            }
        }
    }
}

/// A person's share of their goal in their own color, in a recessed groove.
struct FloodlightProgressBar: View {
    let fraction: Double
    let slot: Int
    var height: CGFloat = 10
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let member = FloodlightToken.member(slot).rgba(scheme)
        let start = member.mixedInOKLab(with: FloodlightMaterial.value(FloodlightMaterial.barDim, scheme), 0.55)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Floodlight.groove)
                    .overlay(Capsule().stroke(FloodlightMaterial.color(FloodlightMaterial.grooveShade), lineWidth: 1).blur(radius: 1.2)
                        .offset(y: 1).clipShape(Capsule()))
                if fraction > 0 {
                    Capsule().fill(LinearGradient(colors: [start.color, member.color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, proxy.size.width * min(1, fraction)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// When a saved update arrived: a sync arrow and "3 min ago", or a clock and
/// the day and time when it's from an earlier day. Given `refresh`, it's also
/// the refresh control, with a spinner in the icon's place while it syncs.
struct FloodlightSyncTime: View {
    let short: String
    let spoken: String
    let late: Bool
    /// `heroMuted` on the lit hero card, where the sky shows through.
    var color = Floodlight.muted
    var refreshing = false
    var refresh: (() -> Void)? = nil
    var body: some View {
        if let refresh {
            // A 44pt target that overhangs the line, so the card keeps its layout.
            Button(action: refresh) {
                label.padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.horizontal, -8).padding(.vertical, -14)
            .accessibilityLabel("Refresh activity")
            .accessibilityValue(refreshing ? "Refreshing" : spoken)
            .accessibilityIdentifier("live.goal.sync")
        } else {
            label.accessibilityElement(children: .ignore).accessibilityLabel(spoken)
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if refreshing {
                // Held to the icon's size so the line doesn't move while it syncs.
                ProgressView().controlSize(.small).tint(color).scaleEffect(0.7).frame(width: 16, height: 14)
            } else {
                Image(systemName: late ? "clock" : "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .semibold))
            }
            Text(short)
        }
        .floodlightFont(12.5, weight: .medium)
        .foregroundStyle(color)
    }
}

// MARK: - Outcome pictures

/// Neutral figures for the pot's four outcomes, drawn for two people or for
/// three or more. They never use a friend's color or rank anyone.
struct FloodlightOutcomePicture: View {
    enum Outcome: CaseIterable { case all, some, none, unconfirmed }
    let outcome: Outcome
    let pair: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 88
            context.scaleBy(x: scale, y: scale)
            paint(&context)
        }
        .aspectRatio(88 / 50, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func paint(_ context: inout GraphicsContext) {
        switch (pair, outcome) {
        case (true, .all):
            person(&context, 24, 20, 10); ok(&context, 31, 27); person(&context, 64, 20, 10); ok(&context, 71, 27)
            coin(&context, 24, 44); coin(&context, 64, 44)
        case (true, .some):
            person(&context, 22, 20, 10); ok(&context, 29, 27); person(&context, 66, 20, 10, miss: true); no(&context, 73, 27)
            coin(&context, 22, 44); coin(&context, 40, 44)
            arrow(&context, [(58, 42)], curve: ((45, 40), (54, 36), (48, 36)), head: [(44.2, 36), (44.6, 40.8), (49.2, 40)])
        case (true, .none):
            person(&context, 24, 20, 10, miss: true); no(&context, 31, 27); person(&context, 64, 20, 10, miss: true); no(&context, 71, 27)
            coin(&context, 24, 44, off: true); coin(&context, 64, 44, off: true)
        case (true, .unconfirmed):
            for x in [26.0, 66] {
                coin(&context, x, 44)
                arrow(&context, [(x - 8, 44)], curve: ((x - 11, 29), (x - 14, 42), (x - 15, 34)),
                      head: [(x - 14.6, 30.4), (x - 11, 29), (x - 10.2, 32.8)], back: true)
            }
            person(&context, 26, 18, 10); ok(&context, 33, 25); person(&context, 66, 18, 10)
            dashedRing(&context, 66, 18, 13); question(&context, 74, 27, 6.2)
        case (false, .all):
            var group = context; group.translateBy(x: 8, y: 3)
            for x in [12.0, 36, 60] { person(&group, x, 17, 8.5); ok(&group, x + 6, 23); coin(&group, x, 38) }
        case (false, .some):
            var group = context; group.translateBy(x: 8, y: 3)
            person(&group, 12, 22, 9, miss: true); no(&group, 18, 29); coin(&group, 30, 22)
            arrow(&group, [(36, 19), (50, 10)], head: [(45.5, 9.2), (50.5, 9.8), (48.6, 14.3)])
            arrow(&group, [(36, 25), (50, 34)], head: [(48.6, 29.7), (50.5, 34.2), (45.5, 34.8)])
            person(&group, 60, 10, 7.5); ok(&group, 66, 15); person(&group, 60, 34, 7.5); ok(&group, 66, 39)
        case (false, .none):
            var group = context; group.translateBy(x: 8, y: 3)
            for x in [12.0, 36, 60] { person(&group, x, 17, 8.5, miss: true); no(&group, x + 6, 23); coin(&group, x, 38, off: true) }
        case (false, .unconfirmed):
            coin(&context, 20, 36)
            arrow(&context, [(22, 28)], curve: ((47, 13), (25, 14), (38, 9)), head: [(42.4, 9.6), (47, 13), (41.8, 14.6)], back: true)
            person(&context, 62, 24, 10.5); dashedRing(&context, 62, 24, 14); question(&context, 71, 34, 6.8)
        }
    }

    private func person(_ context: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, miss: Bool = false) {
        let stops = scheme == .dark ? (miss ? FloodlightMaterial.neutralDim.dark : FloodlightMaterial.neutral.dark)
            : (miss ? FloodlightMaterial.neutralDim.light : FloodlightMaterial.neutral.light)
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: stops.map(\.color)),
            center: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.32), startRadius: 0, endRadius: r * 2 * 0.7))
    }
    private func ok(_ context: inout GraphicsContext, _ x: Double, _ y: Double) {
        var badge = context; badge.translateBy(x: x, y: y)
        badge.fill(Path(ellipseIn: CGRect(x: -5.2, y: -5.2, width: 10.4, height: 10.4)), with: .color(.white))
        var mark = Path(); mark.move(to: CGPoint(x: -2.4, y: 0.1)); mark.addLine(to: CGPoint(x: -0.7, y: 1.8)); mark.addLine(to: CGPoint(x: 2.5, y: -1.6))
        badge.stroke(mark, with: .color(FloodlightRGBA.hex(0x0B1418).color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
    }
    private func no(_ context: inout GraphicsContext, _ x: Double, _ y: Double) {
        var badge = context; badge.translateBy(x: x, y: y)
        badge.fill(Path(ellipseIn: CGRect(x: -5.2, y: -5.2, width: 10.4, height: 10.4)),
                   with: .color(FloodlightMaterial.value(FloodlightMaterial.noFill, scheme).color))
        var mark = Path()
        mark.move(to: CGPoint(x: -1.9, y: -1.9)); mark.addLine(to: CGPoint(x: 1.9, y: 1.9))
        mark.move(to: CGPoint(x: 1.9, y: -1.9)); mark.addLine(to: CGPoint(x: -1.9, y: 1.9))
        badge.stroke(mark, with: .color(.white), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
    }
    private func coin(_ context: inout GraphicsContext, _ x: Double, _ y: Double, off: Bool = false) {
        var piece = context; piece.translateBy(x: x, y: y)
        piece.opacity = off ? 0.35 : 1
        let v = { FloodlightMaterial.value($0, scheme) }
        let circle = Path(ellipseIn: CGRect(x: -5.6, y: -5.6, width: 11.2, height: 11.2))
        piece.fill(circle, with: .radialGradient(Gradient(stops: [.init(color: v(FloodlightMaterial.coinHighlight).color, location: 0),
                                                                  .init(color: v(FloodlightMaterial.coin).color, location: 0.62),
                                                                  .init(color: v(FloodlightMaterial.coinLow).color, location: 1)]),
                                                 center: CGPoint(x: -1.1, y: -2.2), startRadius: 0, endRadius: 8.4))
        piece.stroke(circle, with: .color(v(FloodlightMaterial.coinRing).color), lineWidth: 1)
        piece.stroke(Path(ellipseIn: CGRect(x: -3.4, y: -3.4, width: 6.8, height: 6.8)),
                     with: .color(v(FloodlightMaterial.coinInk).opacity(0.38).color), lineWidth: 0.9)
    }
    private func arrow(_ context: inout GraphicsContext, _ line: [(Double, Double)], curve: ((Double, Double), (Double, Double), (Double, Double))? = nil,
                       head: [(Double, Double)], back: Bool = false) {
        var path = Path()
        path.move(to: CGPoint(x: line[0].0, y: line[0].1))
        for point in line.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        if let curve {
            path.addCurve(to: CGPoint(x: curve.0.0, y: curve.0.1), control1: CGPoint(x: curve.1.0, y: curve.1.1),
                          control2: CGPoint(x: curve.2.0, y: curve.2.1))
        }
        var tip = Path()
        tip.addLines(head.map { CGPoint(x: $0.0, y: $0.1) })
        let color = (back ? FloodlightToken.unconfirmed : FloodlightToken.accent).rgba(scheme).color
        let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        context.stroke(path, with: .color(color), style: style)
        context.stroke(tip, with: .color(color), style: style)
    }
    private func dashedRing(_ context: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double) {
        context.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(FloodlightToken.unconfirmed.rgba(scheme).color), style: StrokeStyle(lineWidth: 1.5, dash: [2.6, 2.4]))
    }
    private func question(_ context: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double) {
        var badge = context; badge.translateBy(x: x, y: y)
        badge.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(FloodlightToken.unconfirmed.rgba(scheme).color))
        let mark = badge.resolve(Text("?").font(.custom(FloodlightFonts.face(.bold, condensed: false), fixedSize: 7.4 * r / 6.8))
            .foregroundColor(FloodlightToken.unconfirmedInk.rgba(scheme).color))
        badge.draw(mark, at: .zero, anchor: .center)
    }
}
