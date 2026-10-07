import SwiftUI

/// HabitTrace color tokens.
///
/// Values mirror the PWA's Tailwind palette and the `@theme` block in
/// `app/globals.css`. Light mode is the parity target for this phase.
enum HTColor {
    // MARK: Brand

    /// `--color-brand` / slate-900. Primary buttons, body text, dark hero cards.
    static let brand = Color(hex: 0x0F172A)
    /// `--color-brand-light` / slate-800.
    static let brandLight = Color(hex: 0x1E293B)
    /// `--color-brand-subtle` / slate-700. Primary button pressed state.
    static let brandSubtle = Color(hex: 0x334155)
    /// slate-950. Hero card and selected-day backgrounds.
    static let ink = Color(hex: 0x020617)

    // MARK: Surfaces

    /// `--color-surface`. Cards.
    static let surface = Color(hex: 0xFFFFFF)
    /// `--color-surface-muted` / slate-50. App background.
    static let surfaceMuted = Color(hex: 0xF8FAFC)
    /// slate-100. Secondary buttons, field backgrounds.
    static let surfaceSecondary = Color(hex: 0xF1F5F9)
    /// `--color-surface-border` / slate-200. Card and tab bar borders.
    static let border = Color(hex: 0xE2E8F0)
    /// slate-300. Field borders, pending status dots.
    static let borderStrong = Color(hex: 0xCBD5E1)

    // MARK: Text

    /// slate-900. Primary text.
    static let textPrimary = Color(hex: 0x0F172A)
    /// slate-700. Secondary button text, strong captions.
    static let textStrong = Color(hex: 0x334155)
    /// slate-600.
    static let textSecondary = Color(hex: 0x475569)
    /// slate-500. Inactive tab labels, muted captions.
    static let textMuted = Color(hex: 0x64748B)
    /// slate-400. Chart ticks, placeholder text.
    static let textTertiary = Color(hex: 0x94A3B8)

    // MARK: Accents (from `--color-accent-*`)

    static let accentEmerald = Color(hex: 0x34D399)
    static let accentSky = Color(hex: 0x38BDF8)
    static let accentViolet = Color(hex: 0xA78BFA)
    static let accentAmber = Color(hex: 0xFBBF24)
    static let accentRose = Color(hex: 0xFB7185)

    // MARK: Semantic: success (emerald)

    static let success50 = Color(hex: 0xECFDF5)
    static let success100 = Color(hex: 0xD1FAE5)
    static let success300 = Color(hex: 0x6EE7B7)
    static let success400 = Color(hex: 0x34D399)
    static let success600 = Color(hex: 0x059669)
    static let success700 = Color(hex: 0x047857)

    // MARK: Semantic: danger (rose)

    static let danger50 = Color(hex: 0xFFF1F2)
    static let danger100 = Color(hex: 0xFFE4E6)
    static let danger300 = Color(hex: 0xFDA4AF)
    static let danger600 = Color(hex: 0xE11D48)
    static let danger700 = Color(hex: 0xBE123C)

    // MARK: Semantic: warning (amber)

    static let warning50 = Color(hex: 0xFFFBEB)
    static let warning100 = Color(hex: 0xFEF3C7)
    static let warning500 = Color(hex: 0xF59E0B)
    static let warning700 = Color(hex: 0xB45309)

    // MARK: Semantic: info (sky)

    static let info50 = Color(hex: 0xF0F9FF)
    static let info100 = Color(hex: 0xE0F2FE)
    static let info700 = Color(hex: 0x0369A1)

    // MARK: Category chips (`bg-X-50 text-X-700 ring-X-100`)

    enum Chip {
        static let sky = ChipPalette(
            background: Color(hex: 0xF0F9FF),
            foreground: Color(hex: 0x0369A1),
            ring: Color(hex: 0xE0F2FE)
        )
        static let violet = ChipPalette(
            background: Color(hex: 0xF5F3FF),
            foreground: Color(hex: 0x6D28D9),
            ring: Color(hex: 0xEDE9FE)
        )
        static let amber = ChipPalette(
            background: Color(hex: 0xFFFBEB),
            foreground: Color(hex: 0xB45309),
            ring: Color(hex: 0xFEF3C7)
        )
        static let emerald = ChipPalette(
            background: Color(hex: 0xECFDF5),
            foreground: Color(hex: 0x047857),
            ring: Color(hex: 0xD1FAE5)
        )
        static let orange = ChipPalette(
            background: Color(hex: 0xFFF7ED),
            foreground: Color(hex: 0xC2410C),
            ring: Color(hex: 0xFFEDD5)
        )
        static let fuchsia = ChipPalette(
            background: Color(hex: 0xFDF4FF),
            foreground: Color(hex: 0xA21CAF),
            ring: Color(hex: 0xFAE8FF)
        )
        static let cyan = ChipPalette(
            background: Color(hex: 0xECFEFF),
            foreground: Color(hex: 0x0E7490),
            ring: Color(hex: 0xCFFAFE)
        )
        static let slate = ChipPalette(
            background: Color(hex: 0xF8FAFC),
            foreground: Color(hex: 0x334155),
            ring: Color(hex: 0xF1F5F9)
        )
    }
}

/// Background, foreground, and ring colors for a small tinted chip.
struct ChipPalette {
    let background: Color
    let foreground: Color
    let ring: Color
}

extension Color {
    /// Creates an opaque color from a `0xRRGGBB` literal.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
