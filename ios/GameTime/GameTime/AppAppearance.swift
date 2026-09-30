import SwiftUI

/// A device preference. System leaves the iPhone in charge of appearance.
enum AppAppearance: String, CaseIterable {
    case system, light, dark
    static let storageKey = "gametime.appearance"

    var title: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
