import CoreText
import SwiftUI
import UIKit

/// Barlow for reading text and Barlow Condensed for titles and numbers, as the
/// adopted Floodlight page embeds them. Both ship under the SIL Open Font
/// License; the license files sit beside the fonts in `Fonts/`.
enum FloodlightFonts {
    static let faces = ["Barlow-Regular", "Barlow-Medium", "Barlow-SemiBold", "Barlow-Bold",
                        "BarlowCondensed-Medium", "BarlowCondensed-SemiBold", "BarlowCondensed-Bold", "BarlowCondensed-ExtraBold"]

    /// Registers the bundled faces for this process on first use. A face that
    /// is already registered counts as available.
    static let registered: Bool = {
        var available = true
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else { available = false; continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
               let failure = error?.takeRetainedValue(),
               CFErrorGetCode(failure) != CTFontManagerError.alreadyRegistered.rawValue {
                available = false
            }
        }
        return available
    }()

    /// The face for a weight: Barlow 400–700, Barlow Condensed 500–800.
    static func face(_ weight: Font.Weight, condensed: Bool) -> String {
        if condensed {
            switch weight {
            case .heavy, .black: return "BarlowCondensed-ExtraBold"
            case .bold: return "BarlowCondensed-Bold"
            case .semibold: return "BarlowCondensed-SemiBold"
            default: return "BarlowCondensed-Medium"
            }
        }
        switch weight {
        case .bold, .heavy, .black: return "Barlow-Bold"
        case .semibold: return "Barlow-SemiBold"
        case .medium: return "Barlow-Medium"
        default: return "Barlow-Regular"
        }
    }

    static func uiFont(_ size: CGFloat, weight: Font.Weight, condensed: Bool = false) -> UIFont {
        _ = registered
        return UIFont(name: face(weight, condensed: condensed), size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }
}

/// A mock's point size in Barlow that grows with the person's text size, the
/// same way `liveFont` scales: relative to the nearest system text style.
/// `maxScale` caps display numbers the way `LiveMetric` does.
struct FloodlightFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    private let condensed: Bool
    private let maxScale: CGFloat?
    init(size: CGFloat, weight: Font.Weight, condensed: Bool, maxScale: CGFloat?) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: LiveFont.style(for: size))
        base = size
        self.weight = weight
        self.condensed = condensed
        self.maxScale = maxScale
    }
    func body(content: Content) -> some View {
        _ = FloodlightFonts.registered
        let scaled = maxScale.map { min(size, base * $0) } ?? size
        return content.font(.custom(FloodlightFonts.face(weight, condensed: condensed), fixedSize: scaled))
    }
}

extension View {
    func floodlightFont(_ size: CGFloat, weight: Font.Weight = .regular, condensed: Bool = false, maxScale: CGFloat? = nil) -> some View {
        modifier(FloodlightFont(size: size, weight: weight, condensed: condensed, maxScale: maxScale))
    }
}

/// The small spaced capitals the page uses for labels ("YOUR STAKE", dates).
/// The capitals are drawn, not spoken: VoiceOver reads the words as written.
struct FloodlightLabel: View {
    let text: String
    var color: Color = Floodlight.muted
    var size: CGFloat = 10.5
    /// What VoiceOver reads instead of the text, when the label stands for more.
    var spoken: String? = nil
    init(_ text: String, color: Color = Floodlight.muted, size: CGFloat = 10.5, spoken: String? = nil) {
        self.text = text; self.color = color; self.size = size; self.spoken = spoken
    }
    var body: some View {
        Text(text.uppercased(with: .current)).floodlightFont(size, weight: .semibold).tracking(size * 0.14).foregroundStyle(color)
            .accessibilityLabel(spoken ?? text)
    }
}

/// A title in Barlow Condensed Bold capitals, read as written.
struct FloodlightTitle: View {
    let text: String
    var size: CGFloat = 44
    var maxScale: CGFloat? = nil
    /// Letter spacing as a share of the size: the page's titles use -0.012em,
    /// its wordmark -0.02em.
    var spacing: CGFloat = -0.012
    init(_ text: String, size: CGFloat = 44, maxScale: CGFloat? = nil, spacing: CGFloat = -0.012) {
        self.text = text; self.size = size; self.maxScale = maxScale; self.spacing = spacing
    }
    var body: some View {
        Text(text.uppercased(with: .current)).floodlightFont(size, weight: .bold, condensed: true, maxScale: maxScale)
            .tracking(size * spacing).accessibilityLabel(text)
    }
}
