import SwiftUI

/// White surface with a slate border and the PWA's soft `shadow-surface`.
///
/// Matches `rounded-2xl border border-slate-200 bg-white p-4`.
struct HTCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat
    var background: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(HTColor.border, lineWidth: 1)
            }
            .shadow(color: HTColor.brand.opacity(0.05), radius: 1, y: 1)
            .shadow(color: HTColor.brand.opacity(0.06), radius: 9, y: 4)
    }
}

/// Dark elevated surface used by the "Up next" hero.
///
/// Matches `rounded-3xl bg-slate-950 p-5 text-white shadow-xl`.
struct HTHeroCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HTColor.ink)
            .clipShape(.rect(cornerRadius: HTRadius.xl, style: .continuous))
            .shadow(color: HTColor.ink.opacity(0.25), radius: 20, y: 12)
    }
}

extension View {
    /// Standard card: white, 1pt slate border, 16pt radius, soft shadow.
    func htCard(
        padding: CGFloat = HTSpacing.cardPadding,
        cornerRadius: CGFloat = HTRadius.lg,
        background: Color = HTColor.surface
    ) -> some View {
        modifier(
            HTCardModifier(
                padding: padding,
                cornerRadius: cornerRadius,
                background: background
            )
        )
    }

    /// Larger panel variant (`.panel`): 20pt radius, 24pt padding.
    func htPanel() -> some View {
        modifier(
            HTCardModifier(
                padding: HTSpacing.xxl,
                cornerRadius: HTRadius.panel,
                background: HTColor.surface
            )
        )
    }

    /// Dark hero surface with 24pt radius.
    func htHeroCard(padding: CGFloat = HTSpacing.heroPadding) -> some View {
        modifier(HTHeroCardModifier(padding: padding))
    }
}

#Preview("Cards") {
    ScrollView {
        VStack(spacing: HTSpacing.md) {
            Text("Standard card")
                .font(.htBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .htCard()

            Text("Panel")
                .font(.htBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .htPanel()

            Text("Hero card")
                .font(.htHeroTitle)
                .foregroundStyle(.white)
                .htHeroCard()
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
