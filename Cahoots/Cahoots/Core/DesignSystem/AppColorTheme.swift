import SwiftUI
import UIKit

/// Selectable brand palettes. Each theme defines light and dark surfaces from a soft/bold pair.
enum AppColorTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case mint
    case sky
    case grove
    case volt
    case studio
    case ember
    case tide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mint: String(localized: "Mint")
        case .sky: String(localized: "Sky")
        case .grove: String(localized: "Grove")
        case .volt: String(localized: "Volt")
        case .studio: String(localized: "Studio")
        case .ember: String(localized: "Ember")
        case .tide: String(localized: "Tide")
        }
    }

    /// Soft / bold swatch colors for the theme picker (independent of appearance).
    var swatchSoft: Color { Color(uiColor: definition.soft) }
    var swatchBold: Color { Color(uiColor: definition.bold) }

    func palette(for style: UIUserInterfaceStyle) -> AppThemePalette {
        style == .dark ? definition.dark : definition.light
    }

    private var definition: ThemeDefinition {
        switch self {
        case .mint:
            // Existing brand: soft mint + near-black
            ThemeDefinition(
                soft: UIColor(hex: 0xD7FFE0),
                bold: UIColor(hex: 0x050505),
                light: AppThemePalette(
                    page: UIColor(hex: 0xD7FFE0),
                    card: UIColor(hex: 0x121212),
                    raised: UIColor(hex: 0x1A1A1A),
                    ink: UIColor(hex: 0x050505),
                    onInk: UIColor(hex: 0xD7FFE0),
                    chip: UIColor(hex: 0xC5F2D2)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x050505),
                    card: UIColor(hex: 0x121212),
                    raised: UIColor(hex: 0x1A1A1A),
                    ink: UIColor(hex: 0xD7FFE0),
                    onInk: UIColor(hex: 0x050505),
                    chip: UIColor(hex: 0x1A1A1A)
                )
            )
        case .sky:
            // #2457FF + #DFF7FF
            ThemeDefinition(
                soft: UIColor(hex: 0xDFF7FF),
                bold: UIColor(hex: 0x2457FF),
                light: AppThemePalette(
                    page: UIColor(hex: 0xDFF7FF),
                    card: UIColor(hex: 0x0B1220),
                    raised: UIColor(hex: 0x141C2E),
                    ink: UIColor(hex: 0x2457FF),
                    onInk: UIColor(hex: 0xDFF7FF),
                    chip: UIColor(hex: 0xC5EBFF)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x0B1220),
                    card: UIColor(hex: 0x121A2C),
                    raised: UIColor(hex: 0x1A2438),
                    ink: UIColor(hex: 0xDFF7FF),
                    onInk: UIColor(hex: 0x0B1220),
                    chip: UIColor(hex: 0x141C2E)
                )
            )
        case .grove:
            // #9FE870 + #163300
            ThemeDefinition(
                soft: UIColor(hex: 0x9FE870),
                bold: UIColor(hex: 0x163300),
                light: AppThemePalette(
                    page: UIColor(hex: 0x9FE870),
                    card: UIColor(hex: 0x0F1A05),
                    raised: UIColor(hex: 0x162408),
                    ink: UIColor(hex: 0x163300),
                    onInk: UIColor(hex: 0x9FE870),
                    chip: UIColor(hex: 0x8AD960)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x163300),
                    card: UIColor(hex: 0x1A3A08),
                    raised: UIColor(hex: 0x214410),
                    ink: UIColor(hex: 0x9FE870),
                    onInk: UIColor(hex: 0x163300),
                    chip: UIColor(hex: 0x1A3A08)
                )
            )
        case .volt:
            // #1F2329 + #B6FF2E
            ThemeDefinition(
                soft: UIColor(hex: 0xB6FF2E),
                bold: UIColor(hex: 0x1F2329),
                light: AppThemePalette(
                    page: UIColor(hex: 0xB6FF2E),
                    card: UIColor(hex: 0x1F2329),
                    raised: UIColor(hex: 0x2A2F36),
                    ink: UIColor(hex: 0x1F2329),
                    onInk: UIColor(hex: 0xB6FF2E),
                    chip: UIColor(hex: 0xA3E628)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x1F2329),
                    card: UIColor(hex: 0x2A2F36),
                    raised: UIColor(hex: 0x353B44),
                    ink: UIColor(hex: 0xB6FF2E),
                    onInk: UIColor(hex: 0x1F2329),
                    chip: UIColor(hex: 0x2A2F36)
                )
            )
        case .studio:
            // #6D28D9 + #D7FF00
            ThemeDefinition(
                soft: UIColor(hex: 0xD7FF00),
                bold: UIColor(hex: 0x6D28D9),
                light: AppThemePalette(
                    page: UIColor(hex: 0xD7FF00),
                    card: UIColor(hex: 0x1A0A33),
                    raised: UIColor(hex: 0x25124A),
                    ink: UIColor(hex: 0x6D28D9),
                    onInk: UIColor(hex: 0xD7FF00),
                    chip: UIColor(hex: 0xC4E800)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x2E1065),
                    card: UIColor(hex: 0x1A0A33),
                    raised: UIColor(hex: 0x3B1A7A),
                    ink: UIColor(hex: 0xD7FF00),
                    onInk: UIColor(hex: 0x2E1065),
                    chip: UIColor(hex: 0x3B1A7A)
                )
            )
        case .ember:
            // Warm coral — energetic fitness feel
            ThemeDefinition(
                soft: UIColor(hex: 0xFFE4D6),
                bold: UIColor(hex: 0xC2410C),
                light: AppThemePalette(
                    page: UIColor(hex: 0xFFE4D6),
                    card: UIColor(hex: 0x1C0A05),
                    raised: UIColor(hex: 0x2A120A),
                    ink: UIColor(hex: 0x9A3412),
                    onInk: UIColor(hex: 0xFFE4D6),
                    chip: UIColor(hex: 0xFFD4C0)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x1C0A05),
                    card: UIColor(hex: 0x2A120A),
                    raised: UIColor(hex: 0x3A1A10),
                    ink: UIColor(hex: 0xFFB089),
                    onInk: UIColor(hex: 0x1C0A05),
                    chip: UIColor(hex: 0x2A120A)
                )
            )
        case .tide:
            // Deep teal — calm accountability
            ThemeDefinition(
                soft: UIColor(hex: 0xD8F5F0),
                bold: UIColor(hex: 0x0F766E),
                light: AppThemePalette(
                    page: UIColor(hex: 0xD8F5F0),
                    card: UIColor(hex: 0x042F2E),
                    raised: UIColor(hex: 0x0A3F3D),
                    ink: UIColor(hex: 0x0F766E),
                    onInk: UIColor(hex: 0xD8F5F0),
                    chip: UIColor(hex: 0xBFECE4)
                ),
                dark: AppThemePalette(
                    page: UIColor(hex: 0x042F2E),
                    card: UIColor(hex: 0x0A3F3D),
                    raised: UIColor(hex: 0x115E59),
                    ink: UIColor(hex: 0x99F6E4),
                    onInk: UIColor(hex: 0x042F2E),
                    chip: UIColor(hex: 0x0A3F3D)
                )
            )
        }
    }
}

struct AppThemePalette: Sendable {
    let page: UIColor
    let card: UIColor
    let raised: UIColor
    let ink: UIColor
    let onInk: UIColor
    let chip: UIColor
}

/// Bridge so static `AppColors` can resolve the active theme without threading environment everywhere.
enum AppColorThemeBridge {
    nonisolated(unsafe) static var current: AppColorTheme = .mint
}

private struct ThemeDefinition {
    let soft: UIColor
    let bold: UIColor
    let light: AppThemePalette
    let dark: AppThemePalette
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
