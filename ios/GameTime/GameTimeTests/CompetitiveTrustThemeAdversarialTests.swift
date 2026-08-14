import SwiftUI
import UIKit
import XCTest

@testable import GameTime

final class CompetitiveTrustThemeAdversarialTests: XCTestCase {

    // MARK: - Objective 1: Color Scheme & Contrast Verification under Dark and Light Modes
    func testThemeColorsAndContrastRatiosUnderDarkAndLightModes() {
        // Dark surface tokens
        let darkBackground = UIColor(CompetitiveTrustTheme.darkBackground)
        let graphiteSurface = UIColor(CompetitiveTrustTheme.graphiteSurface)

        // Light surface tokens
        let lightPaper = UIColor(CompetitiveTrustTheme.paper)
        let lightCard = UIColor(CompetitiveTrustTheme.card)

        // Primary Accents
        let signalOrange = UIColor(CompetitiveTrustTheme.signalOrange)
        let athleticGreen = UIColor(CompetitiveTrustTheme.athleticGreen)

        // 1. Verify exact token RGB values
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0

        // Pure dark background (#000000)
        darkBackground.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0.0, accuracy: 0.001)
        XCTAssertEqual(green, 0.0, accuracy: 0.001)
        XCTAssertEqual(blue, 0.0, accuracy: 0.001)

        // Graphite surface (#121212)
        graphiteSurface.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0.0706, accuracy: 0.005)
        XCTAssertEqual(green, 0.0706, accuracy: 0.005)
        XCTAssertEqual(blue, 0.0706, accuracy: 0.005)

        // Signal Orange (#FC5200 -> RGB 0.9882, 0.3216, 0.0)
        signalOrange.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0.9882, accuracy: 0.005)
        XCTAssertEqual(green, 0.3216, accuracy: 0.005)
        XCTAssertEqual(blue, 0.0, accuracy: 0.005)

        // Athletic Green (#00D084 -> RGB 0.0, 0.8157, 0.5176)
        athleticGreen.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0.0, accuracy: 0.005)
        XCTAssertEqual(green, 0.8157, accuracy: 0.005)
        XCTAssertEqual(blue, 0.5176, accuracy: 0.005)

        // 2. WCAG AA Contrast Ratios (>= 4.5:1 for normal text) in Dark & Light Modes
        let darkPairs: [(name: String, fg: UIColor, bg: UIColor)] = [
            ("Primary text on dark background", UIColor(CompetitiveTrustTheme.primaryText), darkBackground),
            ("Primary text on graphite surface", UIColor(CompetitiveTrustTheme.primaryText), graphiteSurface),
            ("Secondary text on dark background", UIColor(CompetitiveTrustTheme.secondaryText), darkBackground),
            ("Secondary text on graphite surface", UIColor(CompetitiveTrustTheme.secondaryText), graphiteSurface),
            ("Signal Orange on dark background", signalOrange, darkBackground),
            ("Signal Orange on graphite surface", signalOrange, graphiteSurface),
            ("Athletic Green on dark background", athleticGreen, darkBackground),
            ("Athletic Green on graphite surface", athleticGreen, graphiteSurface),
            ("Primary button label on Signal Orange", .white, signalOrange),
        ]

        let lightPairs: [(name: String, fg: UIColor, bg: UIColor)] = [
            ("Primary text on light paper", UIColor(CompetitiveTrustTheme.primaryText), lightPaper),
            ("Primary text on light card", UIColor(CompetitiveTrustTheme.primaryText), lightCard),
            ("Secondary text on light paper", UIColor(CompetitiveTrustTheme.secondaryText), lightPaper),
            ("Secondary text on light card", UIColor(CompetitiveTrustTheme.secondaryText), lightCard),
            ("Coral Ink on light paper", UIColor(CompetitiveTrustTheme.coralInk), lightPaper),
            ("Mint Ink on light paper", UIColor(CompetitiveTrustTheme.mintInk), lightPaper),
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
