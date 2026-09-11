import SwiftUI
import UIKit
import XCTest

@testable import GameTime

final class CompetitiveTrustThemeAdversarialTests: XCTestCase {

    func testSemanticTextAndControlsMeetContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let surfaces = [CompetitiveTrustTheme.canvas, CompetitiveTrustTheme.surface, CompetitiveTrustTheme.selection]
            for surface in surfaces {
                for foreground in [CompetitiveTrustTheme.textPrimary, CompetitiveTrustTheme.textSecondary,
                                   CompetitiveTrustTheme.brand, CompetitiveTrustTheme.error] {
                    XCTAssertGreaterThanOrEqual(calculateContrastRatio(UIColor(foreground), UIColor(surface), style: style), 4.5)
                }
            }
            XCTAssertGreaterThanOrEqual(calculateContrastRatio(UIColor(CompetitiveTrustTheme.onBrand), UIColor(CompetitiveTrustTheme.feature), style: style), 4.5)
            for foreground in [CompetitiveTrustTheme.success, CompetitiveTrustTheme.warning] {
                XCTAssertGreaterThanOrEqual(calculateContrastRatio(UIColor(foreground), UIColor(CompetitiveTrustTheme.canvas), style: style), 4.5)
            }
        }
    }

    func testBundledDisplayFontIsItalicAndScalesForAccessibility() throws {
        let font = try XCTUnwrap(UIFont(name: "BarlowCondensed-BlackItalic", size: 48))
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertNotNil(UIFont(name: "BarlowCondensed-Black", size: 48))
        XCTAssertNotNil(UIFont(name: "HankenGrotesk-Regular", size: 17))
        let metrics = UIFontMetrics(forTextStyle: .largeTitle)
        let regular = metrics.scaledFont(for: font, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let accessible = metrics.scaledFont(for: font, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        XCTAssertGreaterThan(accessible.pointSize, regular.pointSize)
    }

    func testContentThemeDoesNotAddDropShadows() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GameTime/CompetitiveTrustTheme.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(source.contains(".shadow("))
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
