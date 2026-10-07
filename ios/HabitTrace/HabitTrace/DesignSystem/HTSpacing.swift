import SwiftUI

/// Spacing scale, in points. Mirrors the Tailwind steps the PWA uses most.
enum HTSpacing {
    /// 4pt (`gap-1`).
    static let xs: CGFloat = 4
    /// 8pt (`gap-2`).
    static let sm: CGFloat = 8
    /// 12pt (`gap-3`, `space-y-3`).
    static let md: CGFloat = 12
    /// 16pt (`p-4`, `px-4`).
    static let lg: CGFloat = 16
    /// 20pt (`p-5`).
    static let xl: CGFloat = 20
    /// 24pt (`p-6`, `pt-6`).
    static let xxl: CGFloat = 24

    /// Horizontal screen inset (`px-4`).
    static let screenHorizontal: CGFloat = 16
    /// Top inset below the navigation area (`pt-6`).
    static let screenTop: CGFloat = 24
    /// Bottom inset so content clears floating actions (`pb-32`).
    static let screenBottom: CGFloat = 112

    /// Default card padding (`p-4`).
    static let cardPadding: CGFloat = 16
    /// Hero card padding (`p-5`).
    static let heroPadding: CGFloat = 20
}

/// Corner radius scale, in points.
enum HTRadius {
    /// 8pt (`rounded-lg`).
    static let sm: CGFloat = 8
    /// 12pt (`rounded-xl`).
    static let md: CGFloat = 12
    /// 13pt (`.8rem`), used by `.btn-primary`, `.btn-secondary`, `.field`.
    static let control: CGFloat = 13
    /// 16pt (`rounded-2xl`). Cards, chips, hero buttons.
    static let lg: CGFloat = 16
    /// 20pt (`1.25rem`). Panels.
    static let panel: CGFloat = 20
    /// 24pt (`rounded-3xl`). Hero cards and dialogs.
    static let xl: CGFloat = 24
}

/// Minimum heights for interactive controls, in points.
enum HTControlHeight {
    /// 44pt. Standard buttons and fields (`min-h-11`).
    static let standard: CGFloat = 44
    /// 48pt. Tab bar items and compact rows (`min-h-12`).
    static let comfortable: CGFloat = 48
    /// 56pt. Primary calls to action (`min-h-14`).
    static let prominent: CGFloat = 56
}
