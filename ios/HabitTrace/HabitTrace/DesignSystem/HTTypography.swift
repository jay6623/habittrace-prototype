import SwiftUI

/// HabitTrace type scale.
///
/// Each token is built on a system text style so it scales with Dynamic Type.
/// The PWA uses Geist Sans; the system font is the native equivalent.
///
/// | Token          | PWA                                    | Text style |
/// |----------------|----------------------------------------|------------|
/// | pageTitle      | text-2xl font-bold tracking-tight      | title2     |
/// | sectionTitle   | text-lg font-bold                      | title3     |
/// | cardTitle      | text-base font-semibold                | headline   |
/// | body           | text-sm                                | subheadline|
/// | bodyStrong     | text-sm font-semibold                  | subheadline|
/// | caption        | text-xs                                | caption    |
/// | captionStrong  | text-xs font-semibold                  | caption    |
/// | eyebrow        | text-[10px] font-bold uppercase        | caption2   |
/// | statValue      | text-2xl font-bold tabular-nums        | title2     |
/// | heroTitle      | text-xl font-bold (on dark card)       | title3     |
extension Font {
    static let htPageTitle = Font.title2.weight(.bold)
    static let htSectionTitle = Font.title3.weight(.bold)
    static let htCardTitle = Font.headline
    static let htBody = Font.subheadline
    static let htBodyStrong = Font.subheadline.weight(.semibold)
    static let htCaption = Font.caption
    static let htCaptionStrong = Font.caption.weight(.semibold)
    static let htEyebrow = Font.caption2.weight(.bold)
    static let htStatValue = Font.title2.weight(.bold).monospacedDigit()
    static let htHeroTitle = Font.title3.weight(.bold)
    static let htButton = Font.subheadline.weight(.semibold)
}

extension View {
    /// Page title: bold, tight tracking, primary text color.
    func htPageTitle() -> some View {
        font(.htPageTitle)
            .tracking(-0.4)
            .foregroundStyle(HTColor.textPrimary)
    }

    /// Section title used above lists and groups of cards.
    func htSectionTitle() -> some View {
        font(.htSectionTitle)
            .foregroundStyle(HTColor.textPrimary)
    }

    /// Small uppercase label with wide tracking, matching the PWA's
    /// `uppercase tracking-[0.16em]` eyebrow style.
    func htEyebrow(color: Color = HTColor.textMuted) -> some View {
        font(.htEyebrow)
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}
