import SwiftUI
import UIKit
import XCTest

@testable import GameTime

final class SignalThemeAdversarialTests: XCTestCase {

    func testSemanticTextAndControlsMeetContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let surfaces = [SignalTheme.canvas, SignalTheme.surface, SignalTheme.selection]
            for surface in surfaces {
                for foreground in [SignalTheme.textPrimary, SignalTheme.textSecondary,
                                   SignalTheme.accent, SignalTheme.danger] {
                    XCTAssertGreaterThanOrEqual(calculateContrastRatio(UIColor(foreground), UIColor(surface), style: style), 4.5)
                }
            }
            XCTAssertGreaterThanOrEqual(calculateContrastRatio(UIColor(SignalTheme.onAccent), UIColor(SignalTheme.accent), style: style), 4.5)
            for foreground in [SignalTheme.accent, SignalTheme.textPrimary] {
                XCTAssertGreaterThanOrEqual(calculateContrastRatio(UIColor(foreground), UIColor(SignalTheme.canvas), style: style), 4.5)
            }
        }
    }

    func testSystemTypographyScalesAndNoBundledFontsAreRegistered() throws {
        let font = UIFont.systemFont(ofSize: 48, weight: .medium)
        XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.traitCondensed))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "UIAppFonts"))
        XCTAssertTrue(Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)?.isEmpty ?? true)
        let metrics = UIFontMetrics(forTextStyle: .largeTitle)
        let regular = metrics.scaledFont(for: font, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let accessible = metrics.scaledFont(for: font, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        XCTAssertGreaterThan(accessible.pointSize, regular.pointSize)
    }

    func testContentThemeDoesNotAddDropShadows() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GameTime/SignalTheme.swift")
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
