import SwiftUI
import UIKit

/// The 270° group dial from Floodlight 9.3: one recessed track per person in
/// fixed roster order, each arc ending at that person's own goal, and the pot
/// at the center. Geometry and paint follow the adopted page's SVG.
struct FloodlightDial: View {
    enum Kind { case full, compact, mini }
    struct Lane: Equatable, Identifiable {
        let id: UUID
        /// The person's roster slot, which picks their color.
        let slot: Int
        /// Share of their own goal, 0–1. `nil` means no saved update yet.
        let fraction: Double?
        let initials: String
        var met = false
        var late = false
    }

    let kind: Kind
    let lanes: [Lane]
    var potCents: Int? = nil
    /// Dims every other lane, as the page does while a person is selected.
    var selected: UUID? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let geometry = FloodlightDialGeometry(kind)
        // Shadows and glows run past the dial's frame, as the page's SVG does
        // with overflow visible, so the canvas is larger than the layout box.
        Color.clear
            .aspectRatio(geometry.width / geometry.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / geometry.width
                    let margin = 28 * scale
                    Canvas { context, _ in
                        context.translateBy(x: margin, y: margin)
                        context.scaleBy(x: scale, y: scale)
                        FloodlightDialPainter(geometry: geometry, lanes: lanes, potCents: potCents,
                                              selected: selected, scheme: scheme).paint(&context)
                    }
                    .frame(width: proxy.size.width + margin * 2, height: proxy.size.height + margin * 2)
                    .offset(x: -margin, y: -margin)
                }
            }
            .accessibilityHidden(true)
    }

    /// Where the pot sits, as a fraction of the dial's frame, and its diameter
    /// as a fraction of the width. Lets a button cover the pot.
    static func potFrame(_ kind: Kind, count: Int) -> (center: UnitPoint, diameter: CGFloat) {
        let g = FloodlightDialGeometry(kind)
        let hub = g.hubRadius(count: count)
        return (UnitPoint(x: g.cx / g.width, y: g.cy / g.height), (hub + 8) * 2 / g.width)
    }
}

struct FloodlightDialGeometry {
    let width: CGFloat, height: CGFloat, cx: CGFloat, cy: CGFloat
    let plate: CGFloat, tickOut: CGFloat, tickIn: CGFloat, minorIn: CGFloat, orbit0: CGFloat
    let flag: Bool, minor: Bool, kind: FloodlightDial.Kind

    init(_ kind: FloodlightDial.Kind) {
        self.kind = kind
        switch kind {
        case .full:
            (width, height, cx, cy, plate, tickOut, tickIn, minorIn, orbit0) = (390, 338, 195, 170, 166, 157, 146, 151, 128)
            (flag, minor) = (true, true)
        case .compact:
            (width, height, cx, cy, plate, tickOut, tickIn, minorIn, orbit0) = (390, 252, 195, 126, 120, 113, 104, 108.5, 91)
            (flag, minor) = (false, true)
        case .mini:
            (width, height, cx, cy, plate, tickOut, tickIn, minorIn, orbit0) = (240, 222, 120, 116, 112, 106, 98, 102, 88)
            (flag, minor) = (false, false)
        }
    }

    /// Lane spacing, track width, marker radius and initials size per head
    /// count. 2, 4 and 6 are 9.3's; 1 and 3 are 11.1's; 5 sits between 4 and 6.
    func ring(count: Int) -> (spacing: CGFloat, width: CGFloat, token: CGFloat, text: CGFloat) {
        switch (kind, max(1, min(6, count))) {
        case (.full, 1): (0, 26, 15, 12)
        case (.full, 2): (30, 15, 13.5, 11)
        case (.full, 3): (26.5, 13, 12.5, 10.5)
        case (.full, 4): (23.5, 11.5, 11.5, 10)
        case (.full, 5): (19.5, 9.75, 9.5, 0)
        case (.full, _): (15.6, 8, 7.6, 0)
        case (.compact, 1): (0, 18, 9, 0)
        case (.compact, 2): (20, 10, 6.5, 0)
        case (.compact, 3): (17.5, 8.6, 6, 0)
        case (.compact, 4): (15.5, 7.5, 5.6, 0)
        case (.compact, 5): (13, 6.35, 4.9, 0)
        case (.compact, _): (10.6, 5.2, 4.2, 0)
        case (.mini, 1): (0, 18, 0, 0)
        case (.mini, 2): (16, 12, 0, 0)
        case (.mini, 3): (14, 10.5, 0, 0)
        case (.mini, _): (12.5, 9, 0, 0)
        }
    }

    func hubRadius(count: Int) -> CGFloat {
        switch (kind, max(1, min(6, count))) {
        case (.full, 1), (.full, 2): 44
        case (.full, 3): 41
        case (.full, 4): 38
        case (.full, 5): 36.5
        case (.full, _): 35
        case (.compact, 1), (.compact, 2): 34
        case (.compact, 3): 32
        case (.compact, 4): 30
        case (.compact, 5): 28
        case (.compact, _): 26
        case (.mini, let n):
            min(44, orbit0 - CGFloat(n - 1) * ring(count: n).spacing - ring(count: n).width / 2 - 5)
        }
    }

    static func angle(_ fraction: Double) -> Double { (135 + 270 * fraction) * .pi / 180 }
    func point(_ radius: CGFloat, _ fraction: Double) -> CGPoint {
        let a = Self.angle(fraction)
        return CGPoint(x: cx + CGFloat(cos(a)) * radius, y: cy + CGFloat(sin(a)) * radius)
    }
    func arc(_ radius: CGFloat, _ fraction: Double) -> Path {
        var path = Path()
        guard fraction > 0.0005 else { return path }
        path.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: .radians(Self.angle(0)),
                    endAngle: .radians(Self.angle(min(fraction, 0.99999))), clockwise: false)
        return path
    }
}

/// Paints one dial. Values that differ by appearance come from the tokens and
/// the page's Toned material.
struct FloodlightDialPainter {
    let geometry: FloodlightDialGeometry
    let lanes: [FloodlightDial.Lane]
    let potCents: Int?
    let selected: UUID?
    let scheme: ColorScheme

    private var dark: Bool { scheme == .dark }
    private func token(_ token: FloodlightToken) -> FloodlightRGBA { token.rgba(scheme) }
    private func material(_ pair: FloodlightMaterial.Pair) -> FloodlightRGBA { FloodlightMaterial.value(pair, scheme) }

    func paint(_ context: inout GraphicsContext) {
        paintPlate(&context)
        paintTicks(&context)
        if geometry.flag { paintFlag(&context) }
        let ring = geometry.ring(count: lanes.count)
        for (index, lane) in lanes.enumerated() {
            paintLane(&context, lane, radius: geometry.orbit0 - CGFloat(index) * ring.spacing, ring: ring)
        }
        if let potCents {
            let size: CGFloat = switch geometry.kind {
            case .full: potCents >= 10_000 ? 27 : lanes.count == 2 ? 34 : 31
            case .compact: potCents >= 10_000 ? 19 : lanes.count == 2 ? 25 : 22
            case .mini: potCents >= 10_000 ? 32 : 38
            }
            FloodlightPotPainter(center: CGPoint(x: geometry.cx, y: geometry.cy), radius: geometry.hubRadius(count: lanes.count),
                                 rim: geometry.kind == .full ? 3.5 : 2.5, amountSize: size, cents: potCents,
                                 caption: geometry.kind == .mini ? nil : geometry.kind == .compact ? 6.5 : 8, scheme: scheme)
                .paint(&context)
        }
    }

    private func paintPlate(_ context: inout GraphicsContext) {
        let g = geometry
        var shadow = context
        shadow.addFilter(.blur(radius: 10))
        shadow.fill(Path(ellipseIn: CGRect(x: g.cx - g.plate * 0.96, y: g.cy + g.plate * 0.1 - g.plate * 0.92,
                                           width: g.plate * 1.92, height: g.plate * 1.84)),
                    with: .color(material(FloodlightMaterial.plateDrop).color))
        let face = Path(ellipseIn: CGRect(x: g.cx - g.plate, y: g.cy - g.plate, width: g.plate * 2, height: g.plate * 2))
        context.fill(face, with: .radialGradient(
            Gradient(stops: [.init(color: token(.plateTop).color, location: 0), .init(color: token(.plateMid).color, location: 0.6),
                             .init(color: token(.plateBottom).color, location: 1)]),
            center: CGPoint(x: g.cx, y: g.cy - g.plate + (dark ? 0.3 : 0.24) * g.plate * 2), startRadius: 0, endRadius: g.plate * 1.56))
        let rim = g.plate - 0.8
        context.stroke(Path(ellipseIn: CGRect(x: g.cx - rim, y: g.cy - rim, width: rim * 2, height: rim * 2)),
                       with: .linearGradient(Gradient(colors: [token(.plateRimTop).color, token(.plateRimBottom).color]),
                                             startPoint: CGPoint(x: g.cx, y: g.cy - rim), endPoint: CGPoint(x: g.cx, y: g.cy + rim)),
                       lineWidth: 1.6)
        let light = token(.plateLight)
        let sheen = CGRect(x: g.cx - g.plate * 0.76, y: g.cy - g.plate * 0.5 - g.plate * 0.44, width: g.plate * 1.52, height: g.plate * 0.88)
        context.fill(Path(ellipseIn: sheen), with: .linearGradient(Gradient(colors: [light.color, light.opacity(0).color]),
                                                                    startPoint: CGPoint(x: g.cx, y: sheen.minY), endPoint: CGPoint(x: g.cx, y: sheen.maxY)))
    }

    private func paintTicks(_ context: inout GraphicsContext) {
        let g = geometry
        for index in 0...40 {
            let major = index % 10 == 0
            if !major && !g.minor { continue }
            let fraction = Double(index) / 40
            var path = Path()
            path.move(to: g.point(major ? g.tickIn : g.minorIn, fraction))
            path.addLine(to: g.point(g.tickOut, fraction))
            context.stroke(path, with: .color(token(major ? .tickMajor : .tick).color),
                           style: StrokeStyle(lineWidth: major ? 2.2 : 1.1, lineCap: .round))
        }
    }

    /// The finish flag past the end of the dial: a pole and a checkerboard.
    private func paintFlag(_ context: inout GraphicsContext) {
        let spot = geometry.point(150, 1.045)
        var flag = context
        flag.translateBy(x: spot.x, y: spot.y - 6)
        let ink = token(.tickMajor)
        var pole = Path(); pole.move(to: .zero); pole.addLine(to: CGPoint(x: 0, y: 15))
        flag.stroke(pole, with: .color(ink.color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        for (x, y, solid) in [(0.0, 0.0, true), (4, 3, true), (8, 0, true), (0, 6, true), (8, 6, true),
                              (4, 0, false), (0, 3, false), (8, 3, false), (4, 6, false)] {
            flag.fill(Path(CGRect(x: x, y: y, width: 4, height: 3)), with: .color(ink.opacity(solid ? 1 : 0.3).color))
        }
    }

    private func paintLane(_ context: inout GraphicsContext, _ lane: FloodlightDial.Lane, radius: CGFloat,
                           ring: (spacing: CGFloat, width: CGFloat, token: CGFloat, text: CGFloat)) {
        let g = geometry, width = ring.width
        let full = g.arc(radius, 1)
        let round = StrokeStyle(lineWidth: width, lineCap: .round)
        context.stroke(full, with: .color(token(.trackEdge).color), style: StrokeStyle(lineWidth: width + 2, lineCap: .round))
        context.stroke(full, with: .color(token(.track).color), style: round)
        paintInset(&context, outline: full.strokedPath(round))

        let dimmed = selected != nil && selected != lane.id
        let member = token(FloodlightToken.member(lane.slot))
        let arcColor = token(FloodlightToken.arc(lane.slot))
        if let fraction = lane.fraction, fraction > 0.0005 {
            let path = g.arc(radius, fraction)
            let start = g.point(radius, 0), head = g.point(radius, max(fraction, 0.001))
            let tail = arcColor.mixed(with: token(.arcTail), FloodlightNumber.arcTailMix.value(scheme))
            let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: [tail.color, arcColor.color]),
                                                                  startPoint: start, endPoint: head)
            var glow = context
            glow.opacity = FloodlightNumber.arcBloom.value(scheme) * (dimmed ? 0.25 : 1)
            glow.addFilter(.blur(radius: dark ? 4.6 : 3.2))
            glow.stroke(path, with: shading, style: StrokeStyle(lineWidth: width + 3, lineCap: .round))
            if !dark {
                var edge = context
                edge.opacity = 0.4
                edge.stroke(path, with: .color(arcColor.mixed(with: .black, 0.34).color),
                            style: StrokeStyle(lineWidth: width + 1.4, lineCap: .round))
            }
            var stroke = context
            stroke.opacity = dimmed ? FloodlightNumber.arcDim.value(scheme) : 1
            stroke.stroke(path, with: shading, style: round)
            if width >= 6 {
                stroke.stroke(g.arc(radius + width * 0.14, fraction), with: .color(token(.arcHighlight).color),
                              style: StrokeStyle(lineWidth: max(1.2, width * 0.24), lineCap: .round))
            }
        }
        guard ring.token > 0 else { return }
        if let fraction = lane.fraction {
            paintMarker(&context, lane, at: g.point(radius, max(fraction, 0.001)), angle: FloodlightDialGeometry.angle(fraction),
                        member: member, ring: ring)
        } else {
            var marker = context
            let start = g.point(radius, 0)
            marker.translateBy(x: start.x, y: start.y)
            let r = ring.token
            marker.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(token(.muted).color),
                          style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            if ring.text > 0 { drawInitials(&marker, lane.initials, size: ring.text, color: token(.muted)) }
        }
    }

    /// The recess: a dark band inside the top edge and a light one inside the
    /// bottom, like the page's inset filter.
    private func paintInset(_ context: inout GraphicsContext, outline: Path) {
        let bounds = CGRect(x: -40, y: -40, width: geometry.width + 80, height: geometry.height + 80)
        let (dy, blur, shadow, opacity, highlight): (CGFloat, CGFloat, FloodlightRGBA, Double, Double) = dark
            ? (2, 1.8, .black, 0.72, 0.08) : (1.4, 1.3, .hex(0x0B4E80), 0.24, 0.8)
        var inside = context
        inside.clip(to: outline)
        var top = inside
        top.addFilter(.blur(radius: blur))
        var cut = Path(bounds); cut.addPath(outline.offsetBy(dx: 0, dy: dy))
        top.fill(cut, with: .color(shadow.opacity(opacity).color), style: FillStyle(eoFill: true))
        var bottom = inside
        bottom.addFilter(.blur(radius: 1.1))
        var lift = Path(bounds); lift.addPath(outline.offsetBy(dx: 0, dy: -1.6))
        bottom.fill(lift, with: .color(FloodlightRGBA.white.opacity(highlight).color), style: FillStyle(eoFill: true))
    }

    private func paintMarker(_ context: inout GraphicsContext, _ lane: FloodlightDial.Lane, at point: CGPoint, angle: Double,
                             member: FloodlightRGBA, ring: (spacing: CGFloat, width: CGFloat, token: CGFloat, text: CGFloat)) {
        let r = ring.token
        var marker = context
        marker.translateBy(x: point.x, y: point.y)
        var drop = marker
        drop.addFilter(.blur(radius: 2.3))
        drop.fill(Path(ellipseIn: CGRect(x: -r * 0.95, y: r * 0.62 - r * 0.5, width: r * 1.9, height: r)),
                  with: .color(material(FloodlightMaterial.tokenDrop).color))
        if dark {
            var halo = marker
            halo.opacity = 0.08
            halo.addFilter(.blur(radius: 4.6))
            halo.fill(Path(ellipseIn: CGRect(x: -r - 4, y: -r - 4, width: (r + 4) * 2, height: (r + 4) * 2)), with: .color(member.color))
        }
        if selected == lane.id {
            let ringRadius = r + 4.5
            marker.stroke(Path(ellipseIn: CGRect(x: -ringRadius, y: -ringRadius, width: ringRadius * 2, height: ringRadius * 2)),
                          with: .color(token(.ink).color), lineWidth: 1.8)
        }
        marker.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(member.color))
        if ring.text > 0 {
            drawInitials(&marker, lane.initials, size: ring.text, color: FloodlightMaterial.initialsInk(member, scheme))
            // Badges sit on the tangent: a check ahead of the head, a clock behind it.
            let distance = r * 1.02
            let tangent = CGPoint(x: -CGFloat(sin(angle)) * distance, y: CGFloat(cos(angle)) * distance)
            if lane.met { paintBadge(&marker, at: tangent, radius: r > 12 ? 6.4 : 5.6, check: true) }
            if lane.late { paintBadge(&marker, at: CGPoint(x: -tangent.x, y: -tangent.y), radius: r > 12 ? 6.4 : 5.6, check: false) }
        } else if lane.met && r >= 6.5 {
            var check = Path()
            check.move(to: CGPoint(x: -2.8, y: 0.1)); check.addLine(to: CGPoint(x: -0.8, y: 2)); check.addLine(to: CGPoint(x: 2.8, y: -1.8))
            marker.stroke(check, with: .color(FloodlightRGBA.hex(0x0B1418).color),
                          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func paintBadge(_ context: inout GraphicsContext, at point: CGPoint, radius: CGFloat, check: Bool) {
        var badge = context
        badge.translateBy(x: point.x, y: point.y)
        let circle = Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        badge.fill(circle, with: .color(.white))
        badge.stroke(circle, with: .color(.black.opacity(0.25)), lineWidth: 0.8)
        var mark = Path()
        if check {
            mark.move(to: CGPoint(x: -2.8, y: 0.2)); mark.addLine(to: CGPoint(x: -0.8, y: 2.2)); mark.addLine(to: CGPoint(x: 3, y: -1.9))
        } else {
            mark.move(to: CGPoint(x: 0, y: -3)); mark.addLine(to: .zero); mark.addLine(to: CGPoint(x: 2, y: 1.3))
        }
        badge.stroke(mark, with: .color(FloodlightRGBA.hex(0x0B1418).color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func drawInitials(_ context: inout GraphicsContext, _ initials: String, size: CGFloat, color: FloodlightRGBA) {
        let text = context.resolve(Text(initials).font(.custom(FloodlightFonts.face(.bold, condensed: false), fixedSize: size))
            .tracking(-size * 0.02).foregroundColor(color.color))
        context.draw(text, at: .zero, anchor: .center)
    }
}

/// The pot: a soft drop, a bezel, a deep blue disc with a thin crescent, the
/// "POT" caption and the amount.
struct FloodlightPotPainter {
    let center: CGPoint
    let radius: CGFloat
    let rim: CGFloat
    let amountSize: CGFloat
    let cents: Int
    /// The caption's point size, or nil for no caption.
    let caption: CGFloat?
    let scheme: ColorScheme

    func paint(_ context: inout GraphicsContext) {
        let dark = scheme == .dark
        let (cx, cy, hub) = (center.x, center.y, radius)
        var shadow = context
        shadow.addFilter(.blur(radius: 2.3))
        shadow.fill(Path(ellipseIn: CGRect(x: cx - hub * 1.02, y: cy + hub * 0.4 - hub * 0.8, width: hub * 2.04, height: hub * 1.6)),
                    with: .color(FloodlightMaterial.value(FloodlightMaterial.hubDrop, scheme).color))
        let outer = hub + rim
        context.fill(Path(ellipseIn: CGRect(x: cx - outer, y: cy - outer, width: outer * 2, height: outer * 2)),
                     with: .linearGradient(Gradient(colors: [FloodlightToken.potRimTop.rgba(scheme).color, FloodlightToken.potRimBottom.rgba(scheme).color]),
                                           startPoint: CGPoint(x: cx, y: cy - outer), endPoint: CGPoint(x: cx, y: cy + outer)))
        context.fill(Path(ellipseIn: CGRect(x: cx - hub, y: cy - hub, width: hub * 2, height: hub * 2)), with: .radialGradient(
            Gradient(stops: [.init(color: FloodlightToken.potTop.rgba(scheme).color, location: 0),
                             .init(color: FloodlightToken.potMid.rgba(scheme).color, location: 0.5),
                             .init(color: FloodlightToken.potBottom.rgba(scheme).color, location: 1)]),
            center: CGPoint(x: cx, y: cy - hub + (dark ? 0.3 : 0.28) * hub * 2), startRadius: 0, endRadius: hub * 1.6))
        let shine = FloodlightToken.potShine.rgba(scheme)
        let crescent = CGRect(x: cx - hub * 0.56, y: cy - hub * 0.66 - hub * 0.22, width: hub * 1.12, height: hub * 0.44)
        context.fill(Path(ellipseIn: crescent), with: .linearGradient(Gradient(colors: [shine.color, shine.opacity(0).color]),
                                                                     startPoint: CGPoint(x: cx, y: crescent.minY), endPoint: CGPoint(x: cx, y: crescent.maxY)))
        if let caption {
            drawText(&context, "POT", font: FloodlightFonts.uiFont(caption, weight: .bold), tracking: caption * 0.2,
                     color: FloodlightToken.potLabel.rgba(scheme), baseline: CGPoint(x: cx, y: cy - hub * 0.36))
        }
        drawText(&context, LiveChallengePresentation.money(cents), font: FloodlightFonts.uiFont(amountSize, weight: .semibold, condensed: true),
                 tracking: -amountSize * 0.01, color: FloodlightToken.potInk.rgba(scheme),
                 baseline: CGPoint(x: cx, y: cy + amountSize * (caption == nil ? 0.34 : 0.44)), fit: hub * 1.7)
    }

    /// Draws centered text with its baseline where the SVG puts it.
    private func drawText(_ context: inout GraphicsContext, _ string: String, font: UIFont, tracking: CGFloat,
                          color: FloodlightRGBA, baseline: CGPoint, fit: CGFloat? = nil) {
        var size = font.pointSize
        var resolved = context.resolve(Text(string).font(.custom(font.fontName, fixedSize: size)).tracking(tracking).monospacedDigit()
            .foregroundColor(color.color))
        var measured = resolved.measure(in: CGSize(width: 1000, height: 1000))
        if let fit, measured.width > fit {
            size *= fit / measured.width
            resolved = context.resolve(Text(string).font(.custom(font.fontName, fixedSize: size)).tracking(tracking).monospacedDigit()
                .foregroundColor(color.color))
            measured = resolved.measure(in: CGSize(width: 1000, height: 1000))
        }
        let top = resolved.firstBaseline(in: measured)
        context.draw(resolved, in: CGRect(x: baseline.x - measured.width / 2, y: baseline.y - top, width: measured.width, height: measured.height))
    }
}

/// The lobby pot from Floodlight 11.1: people who agreed sit filled around a
/// pot that counts only them; people still deciding wait in dashed seats.
struct FloodlightLobbyPot: View {
    struct Seat: Equatable {
        let slot: Int
        let initials: String
        let agreed: Bool
    }
    let seats: [Seat]
    let potCents: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 200
            context.scaleBy(x: scale, y: scale)
            let muted = FloodlightToken.muted.rgba(scheme)
            let (cx, cy, orbit): (CGFloat, CGFloat, CGFloat) = (100, 96, 76)
            context.stroke(Path(ellipseIn: CGRect(x: cx - orbit, y: cy - orbit, width: orbit * 2, height: orbit * 2)),
                           with: .color(muted.opacity(0.35).color), style: StrokeStyle(lineWidth: 1.2, dash: [2, 5]))
            FloodlightPotPainter(center: CGPoint(x: cx, y: cy), radius: 44, rim: 3, amountSize: potCents >= 10_000 ? 28 : 34,
                                 cents: potCents, caption: nil, scheme: scheme).paint(&context)
            let count = max(seats.count, 1)
            for (index, seat) in seats.enumerated() {
                let angle = (-90 + Double(index) * 360 / Double(count)) * .pi / 180
                var spot = context
                spot.translateBy(x: cx + CGFloat(cos(angle)) * orbit, y: cy + CGFloat(sin(angle)) * orbit)
                let member = FloodlightToken.member(seat.slot).rgba(scheme)
                if seat.agreed {
                    spot.fill(Path(ellipseIn: CGRect(x: -17, y: -17, width: 34, height: 34)), with: .color(member.color))
                    let text = spot.resolve(Text(seat.initials).font(.custom(FloodlightFonts.face(.bold, condensed: false), fixedSize: 12))
                        .foregroundColor(FloodlightMaterial.initialsInk(member, scheme).color))
                    spot.draw(text, at: .zero, anchor: .center)
                } else {
                    spot.fill(Path(ellipseIn: CGRect(x: -17, y: -17, width: 34, height: 34)), with: .color(FloodlightToken.ground.rgba(scheme).opacity(0.5).color))
                    spot.stroke(Path(ellipseIn: CGRect(x: -17, y: -17, width: 34, height: 34)), with: .color(muted.color),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    spot.fill(Path(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20)), with: .color(member.color))
                }
            }
        }
        .aspectRatio(200 / 192, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
