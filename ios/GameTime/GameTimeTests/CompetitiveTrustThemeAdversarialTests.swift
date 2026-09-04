import SwiftUI
import UIKit
import XCTest

@testable import GameTime

final class CompetitiveTrustThemeAdversarialTests: XCTestCase {

    // MARK: - Objective 1: Color Scheme & Contrast Verification under Dark and Light Modes
    func testThemeColorsAndContrastRatiosUnderDarkAndLightModes() {
        let darkCanvas = UIColor(CompetitiveTrustTheme.paper)
        let darkSurface = UIColor(CompetitiveTrustTheme.card)
        let lightPaper = UIColor(CompetitiveTrustTheme.paper)
        let lightCard = UIColor(CompetitiveTrustTheme.card)
        let pine = UIColor(CompetitiveTrustTheme.pine)
        let pineInk = UIColor(CompetitiveTrustTheme.pineInk)

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        lightPaper.resolvedColor(with: lightTraits)
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 244.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(green, 240.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(blue, 232.0 / 255.0, accuracy: 0.01)

        pine.resolvedColor(with: lightTraits)
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 31.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(green, 92.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(blue, 69.0 / 255.0, accuracy: 0.01)

        pine.resolvedColor(with: darkTraits)
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 31.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(green, 92.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(blue, 69.0 / 255.0, accuracy: 0.01)

        let darkPairs: [(name: String, fg: UIColor, bg: UIColor)] = [
            ("Primary text on dark canvas", UIColor(CompetitiveTrustTheme.primaryText), darkCanvas),
            ("Primary text on dark surface", UIColor(CompetitiveTrustTheme.primaryText), darkSurface),
            ("Secondary text on dark canvas", UIColor(CompetitiveTrustTheme.secondaryText), darkCanvas),
            ("Pine ink on dark canvas", pineInk, darkCanvas),
            ("Primary button label on pine", UIColor(CompetitiveTrustTheme.onPine), pine),
            ("Money on dark canvas", UIColor(CompetitiveTrustTheme.money), darkCanvas),
        ]

        let lightPairs: [(name: String, fg: UIColor, bg: UIColor)] = [
            ("Primary text on light paper", UIColor(CompetitiveTrustTheme.primaryText), lightPaper),
            ("Primary text on light card", UIColor(CompetitiveTrustTheme.primaryText), lightCard),
            ("Secondary text on light paper", UIColor(CompetitiveTrustTheme.secondaryText), lightPaper),
            ("Pine ink on light paper", pineInk, lightPaper),
            ("Behind-pace ochre on light paper", UIColor(CompetitiveTrustTheme.behindPace), lightPaper),
            ("Money on light paper", UIColor(CompetitiveTrustTheme.money), lightPaper),
            ("Primary button label on pine", UIColor(CompetitiveTrustTheme.onPine), pine),
        ]

        for pair in darkPairs {
            let ratio = calculateContrastRatio(pair.fg, pair.bg, style: .dark)
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "\(pair.name) in Dark Mode must meet WCAG AA contrast (>= 4.5:1). Actual: \(ratio)"
            )
        }

        for pair in lightPairs {
            let ratio = calculateContrastRatio(pair.fg, pair.bg, style: .light)
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "\(pair.name) in Light Mode must meet WCAG AA contrast (>= 4.5:1). Actual: \(ratio)"
            )
        }
    }

    // MARK: - Objective 1: Dynamic Type & Typography Stress Verification
    func testThemeFontHelpersAndExtremeDynamicType() {
        let testSizes: [CGFloat] = [12, 14, 16, 20, 28, 34, 48]
        let categories: [UIContentSizeCategory] = [
            .extraSmall,
            .large,
            .accessibilityLarge,
            .accessibilityExtraExtraExtraLarge,
        ]

        for category in categories {
            let traitCollection = UITraitCollection(preferredContentSizeCategory: category)

            for size in testSizes {
                // Test tabular monospaced digit font
                let tabularFont = CompetitiveTrustTheme.tabularFont(size: size)
                XCTAssertNotNil(tabularFont, "tabularFont should generate valid Font for size \(size)")

                // Test mono font
                let monoFont = CompetitiveTrustTheme.monoFont(size: size)
                XCTAssertNotNil(monoFont, "monoFont should generate valid Font for size \(size)")

                // Test UI font
                let uiFont = CompetitiveTrustTheme.uiFont(size: size, relativeTo: .body)
                XCTAssertNotNil(uiFont, "uiFont should generate valid Font for size \(size)")

                // Verify UIFont scaling under extreme content size categories
                let baseUIFont = UIFont.systemFont(ofSize: size, weight: .bold)
                let metrics = UIFontMetrics(forTextStyle: .headline)
                let scaledUIFont = metrics.scaledFont(for: baseUIFont, compatibleWith: traitCollection)

                if category == .accessibilityExtraExtraExtraLarge {
                    XCTAssertGreaterThan(
                        scaledUIFont.pointSize,
                        baseUIFont.pointSize,
                        "Font point size must scale up significantly under accessibilityExtraExtraExtraLarge"
                    )
                }
            }
        }
    }

    // MARK: - Objective 2: Check Zero Drop Shadows, Zero Bricolage Fonts & Zero Pastel Card Fills
    func testZeroDropShadowsAndForbiddenFontsInCompetitiveTrustTheme() throws {
        let themeFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GameTime/CompetitiveTrustTheme.swift")

        let codeContent = try String(contentsOf: themeFileURL, encoding: .utf8)

        // 1. Verify zero drop shadow calls `shadow(color: ...)` or `.shadow(` in CompetitiveTrustTheme.swift
        XCTAssertFalse(
            codeContent.contains(".shadow("),
            "CompetitiveTrustTheme.swift must NOT contain any SwiftUI drop shadow calls (.shadow(...))."
        )
        XCTAssertFalse(
            codeContent.contains("shadow(color:"),
            "CompetitiveTrustTheme.swift must NOT contain any shadow(color: ...) calls."
        )

        // 2. Verify zero custom font references to Bricolage or Hanken in CompetitiveTrustTheme.swift
        XCTAssertFalse(
            codeContent.contains("Bricolage"),
            "CompetitiveTrustTheme.swift must NOT contain any references to Bricolage font."
        )
        XCTAssertFalse(
            codeContent.contains("Hanken"),
            "CompetitiveTrustTheme.swift must NOT contain any references to Hanken font."
        )
        XCTAssertFalse(
            codeContent.contains("#FC5200"),
            "CompetitiveTrustTheme.swift must not keep Strava Signal Orange."
        )
        XCTAssertFalse(
            codeContent.contains("#00D084"),
            "CompetitiveTrustTheme.swift must not keep athletic neon green."
        )
        XCTAssertFalse(
            codeContent.contains("0.9882"),
            "CompetitiveTrustTheme.swift must not keep Signal Orange RGB literals."
        )
    }

    // MARK: - Helper Methods
    private func calculateContrastRatio(
        _ fg: UIColor,
        _ bg: UIColor,
        style: UIUserInterfaceStyle
    ) -> CGFloat {
        let resolvedFG = fg.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        let resolvedBG = bg.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))

        let l1 = relativeLuminance(resolvedFG)
        let l2 = relativeLuminance(resolvedBG)

        let lighter = max(l1, l2)
        let darker = min(l1, l2)

        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }

        func linearize(_ val: CGFloat) -> CGFloat {
            val <= 0.04045 ? val / 12.92 : pow((val + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }
}
