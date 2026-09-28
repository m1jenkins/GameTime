import SwiftUI
import UIKit
import XCTest

@testable import GameTime

/// The native Floodlight tokens against the adopted page, re-measured here as
/// the 9.3 adoption asked ("faint" and the pot bar top pass with little margin).
final class FloodlightThemeTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let rounds = root.appendingPathComponent(".lavish/floodlight-refinement-2026-09-27")

    /// Every `--gt-*` value in a round's `[data-mode=light|dark]{…}` blocks.
    private func cssTokens(_ round: String) throws -> (light: [String: String], dark: [String: String]) {
        let html = try String(contentsOf: Self.rounds.appendingPathComponent(round + "/index.html"), encoding: .utf8)
        func block(_ mode: String) throws -> [String: String] {
            let blocks = try NSRegularExpression(pattern: "(?m)^\\[data-mode=\(mode)\\]\\{([^}]*)\\}")
            let pairs = try NSRegularExpression(pattern: "--gt-([a-z0-9-]+):([^;}]+)")
            var tokens: [String: String] = [:]
            for match in blocks.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                let body = String(html[Range(match.range(at: 1), in: html)!])
                for pair in pairs.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                    tokens[String(body[Range(pair.range(at: 1), in: body)!])] = String(body[Range(pair.range(at: 2), in: body)!]).trimmingCharacters(in: .whitespaces)
                }
            }
            return tokens
        }
        return (try block("light"), try block("dark"))
    }

    private func parse(_ css: String) -> FloodlightRGBA? {
        if css.hasPrefix("#"), css.count == 7, let value = UInt32(css.dropFirst(), radix: 16) { return .hex(value) }
        guard css.hasPrefix("rgba("), css.hasSuffix(")") else { return nil }
        let parts = css.dropFirst(5).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 4 ? .rgba(parts[0], parts[1], parts[2], parts[3]) : nil
    }

    private func assertMatches(_ token: FloodlightToken, _ css: String?, _ value: FloodlightRGBA, _ mode: String, round: String) {
        guard let css, let parsed = parse(css) else { return XCTFail("\(round) has no \(mode) --gt-\(token.rawValue)") }
        XCTAssertEqual(parsed, value, "\(round) \(mode) --gt-\(token.rawValue) is \(css)")
    }

    func testEveryColorTokenMatchesTheAdoptedPage() throws {
        let adopted = try cssTokens("round-9-3")
        let latest = try cssTokens("round-11-1")
        for token in FloodlightToken.allCases {
            // 9.3 is the adopted table; 11.1 must not have moved any of it.
            for (round, css) in (token.adoptedIn93 ? [("round-9-3", adopted), ("round-11-1", latest)] : [("round-11-1", latest)]) {
                assertMatches(token, css.light[token.rawValue], token.values.light, "light", round: round)
                assertMatches(token, css.dark[token.rawValue], token.values.dark, "dark", round: round)
            }
        }
        for number in FloodlightNumber.allCases {
            XCTAssertEqual(adopted.light[number.rawValue].flatMap(Double.init), number.values.light, number.rawValue)
            XCTAssertEqual(adopted.dark[number.rawValue].flatMap(Double.init), number.values.dark, number.rawValue)
        }
        // The table's 71 rows: 63 colors, 4 numbers and 4 shadow or material modifiers.
        XCTAssertEqual(FloodlightToken.allCases.filter(\.adoptedIn93).count + FloodlightNumber.allCases.count + 4, 71)
        let modifiers = ["hero-material", "hero-shadow", "card-shadow", "button-shadow"]
        let adoptedNames = Set(FloodlightToken.allCases.filter(\.adoptedIn93).map(\.rawValue) + FloodlightNumber.allCases.map(\.rawValue) + modifiers)
        XCTAssertEqual(Set(adopted.light.keys), adoptedNames, "A 9.3 token has no native value, or the reverse")
    }

    func testColorsResolveWithTheViewsAppearance() {
        for token in FloodlightToken.allCases {
            for (style, expected) in [(UIUserInterfaceStyle.light, token.values.light), (.dark, token.values.dark)] {
                let resolved = UIColor(token.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
                XCTAssertEqual(Double(r * 255), expected.red, accuracy: 0.5, "\(token) \(style.rawValue)")
                XCTAssertEqual(Double(g * 255), expected.green, accuracy: 0.5, "\(token) \(style.rawValue)")
                XCTAssertEqual(Double(b * 255), expected.blue, accuracy: 0.5, "\(token) \(style.rawValue)")
                XCTAssertEqual(Double(a), expected.alpha, accuracy: 0.005, "\(token) \(style.rawValue)")
            }
        }
    }

    /// Text at 4.5:1 and arcs at 3:1, measured on the colors the phone draws,
    /// with translucent tokens composited over what sits behind them.
    func testTextAndArcContrastInBothAppearances() {
        for scheme in [ColorScheme.light, .dark] {
            func v(_ token: FloodlightToken) -> FloodlightRGBA { token.rgba(scheme) }
            let text: [(FloodlightToken, FloodlightToken, String)] = [
                (.ink, .ground, "ink on ground"), (.ink, .card, "ink on card"), (.ink, .sheet, "ink on sheet"), (.ink, .well, "ink on well"),
                (.muted, .ground, "muted on ground"), (.muted, .card, "muted on card"), (.muted, .well, "muted on well"), (.muted, .sheet, "muted on sheet"),
                (.heroMuted, .backdrop3, "hero muted on the sky"), (.heroMuted, .backdrop4, "hero muted low on the sky"),
                (.faint, .bar, "inactive tab label"), (.buttonInk, .button, "button label"), (.link, .card, "link"),
                (.potLabel, .potTop, "POT caption"), (.potInk, .potTop, "pot amount"), (.potInk, .potBarTop, "pot bar amount"),
                (.unconfirmedInk, .unconfirmed, "Couldn't confirm badge"), (.ink, .unconfirmedWash, "ink on the Couldn't confirm card")
            ]
            for (foreground, background, pair) in text {
                let ratio = contrast(v(foreground), over: v(background))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(pair), \(scheme): \(ratio)")
            }
            for (index, arc) in FloodlightToken.arcSlots.enumerated() {
                XCTAssertGreaterThanOrEqual(contrast(v(arc), over: v(.track)), 3, "arc \(index) head on its track, \(scheme)")
            }
        }
        // Initials on each person's color, the size of small text.
        for scheme in [ColorScheme.light, .dark] {
            for slot in 0..<6 {
                let member = FloodlightToken.member(slot).rgba(scheme)
                let ratio = contrast(FloodlightMaterial.initialsInk(member, scheme), over: member)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "initials on slot \(slot), \(scheme): \(ratio)")
            }
        }
        // The two light values 9.3 passed by a hair stay above the line natively.
        XCTAssertGreaterThanOrEqual(contrast(FloodlightToken.faint.values.light, over: FloodlightToken.bar.values.light), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(FloodlightToken.potInk.values.light, over: FloodlightToken.potBarTop.values.light), 4.5)
    }

    func testBundledBarlowRegistersWithItsLicenseAndScalesWithTextSize() throws {
        XCTAssertTrue(FloodlightFonts.registered)
        for face in FloodlightFonts.faces {
            XCTAssertNotNil(UIFont(name: face, size: 17), "\(face) is not registered")
        }
        XCTAssertEqual(FloodlightFonts.face(.semibold, condensed: true), "BarlowCondensed-SemiBold")
        XCTAssertEqual(FloodlightFonts.face(.regular, condensed: false), "Barlow-Regular")
        XCTAssertEqual(FloodlightFonts.face(.black, condensed: true), "BarlowCondensed-ExtraBold")
        for license in ["barlow-OFL", "barlowcondensed-OFL"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: license, withExtension: "txt"))
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
            XCTAssertTrue(text.contains("Copyright 2017 The Barlow Project Authors"))
        }
        // Barlow sizes scale like liveFont: with the nearest system text style.
        let metrics = UIFontMetrics(forTextStyle: UIFont.TextStyle(LiveFont.style(for: 15)))
        let regular = metrics.scaledValue(for: 15, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let accessible = metrics.scaledValue(for: 15, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        XCTAssertEqual(regular, 15, accuracy: 0.01)
        XCTAssertGreaterThan(accessible, regular * 1.5)
    }

    private func contrast(_ foreground: FloodlightRGBA, over background: FloodlightRGBA) -> Double {
        let base = background.alpha < 1 ? background.composited(over: .white) : background
        let top = foreground.composited(over: base)
        let (a, b) = (top.luminance, base.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

private extension FloodlightRGBA {
    func composited(over background: FloodlightRGBA) -> FloodlightRGBA {
        .rgba(red * alpha + background.red * (1 - alpha), green * alpha + background.green * (1 - alpha),
              blue * alpha + background.blue * (1 - alpha), 1)
    }
    var luminance: Double {
        func linear(_ c: Double) -> Double { let v = c / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

private extension UIFont.TextStyle {
    init(_ style: Font.TextStyle) {
        switch style {
        case .largeTitle: self = .largeTitle
        case .title: self = .title1
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .body: self = .body
        case .callout: self = .callout
        case .subheadline: self = .subheadline
        case .footnote: self = .footnote
        case .caption: self = .caption1
        default: self = .caption2
        }
    }
}
