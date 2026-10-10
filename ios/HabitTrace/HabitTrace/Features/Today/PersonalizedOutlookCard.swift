import SwiftUI

/// Presentation model for the personalized outlook card.
///
/// The backend exposes this at `GET /analytics/personalized-outlook`, but
/// the iOS API client does not call it yet. Until it does, the card is
/// rendered from `PersonalizedOutlook.sample` and labeled as sample data.
struct PersonalizedOutlook {
    /// 0...1 probability shown as a percentage badge.
    let successProbability: Double
    let strongestPlan: String
    let strongestDetail: String
    let needsAttention: String
    let attentionDetail: String
    let suggestion: String
    let sampleCount: Int
    let confidence: String
    /// True when the values are illustrative rather than fetched.
    let isSample: Bool

    /// Illustrative content for layout only. Never shown as real data.
    static let sample = PersonalizedOutlook(
        successProbability: 0.72,
        strongestPlan: "Morning study blocks",
        strongestDetail: "You finish most plans that start before 10 AM.",
        needsAttention: "Late evening chores",
        attentionDetail: "Plans after 8 PM are the ones most often skipped.",
        suggestion: "Move one evening plan to the early afternoon.",
        sampleCount: 24,
        confidence: "Low",
        isSample: true
    )
}

/// Emerald outlook card from the PWA Today screen.
struct PersonalizedOutlookCard: View {
    let outlook: PersonalizedOutlook

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .center) {
                HTEyebrowLabel(
                    text: "Personalized outlook · Experimental",
                    color: HTColor.success700
                )

                Spacer(minLength: HTSpacing.sm)

                if outlook.isSample {
                    sampleBadge
                }
            }

            HStack(alignment: .center, spacing: HTSpacing.md) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text("Today's completion outlook")
                        .font(.htCardTitle)
                        .foregroundStyle(HTColor.textPrimary)

                    Text("Based on how similar plans have gone for you.")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textSecondary)
                }

                Spacer(minLength: 0)

                probabilityBadge
            }

            insightBox(
                label: "Strongest plan",
                title: outlook.strongestPlan,
                detail: outlook.strongestDetail,
                background: HTColor.surface,
                labelColor: HTColor.success700
            )

            insightBox(
                label: "Needs attention",
                title: outlook.needsAttention,
                detail: outlook.attentionDetail,
                background: HTColor.warning50,
                labelColor: HTColor.warning700
            )

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                HTEyebrowLabel(text: "One thing to try", color: HTColor.textMuted)

                Text(outlook.suggestion)
                    .font(.htBody)
                    .foregroundStyle(HTColor.textPrimary)
            }

            HTMetaText(
                "\(outlook.sampleCount) logged plans",
                "\(outlook.confidence) confidence"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HTSpacing.cardPadding)
        .background(
            LinearGradient(
                colors: [HTColor.success50, HTColor.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                .strokeBorder(HTColor.success100, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var probabilityBadge: some View {
        Text(outlook.successProbability, format: .percent.precision(.fractionLength(0)))
            .font(.htStatValue)
            .foregroundStyle(.white)
            .padding(.horizontal, HTSpacing.md)
            .padding(.vertical, HTSpacing.sm)
            .background(HTColor.success700)
            .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
            .accessibilityLabel("Completion outlook")
    }

    private var sampleBadge: some View {
        Text("Sample data")
            .font(.htEyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(HTColor.warning700)
            .padding(.horizontal, HTSpacing.sm)
            .padding(.vertical, HTSpacing.xs)
            .background(HTColor.warning100)
            .clipShape(Capsule())
    }

    private func insightBox(
        label: String,
        title: String,
        detail: String,
        background: Color,
        labelColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            HTEyebrowLabel(text: label, color: labelColor)

            Text(title)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)

            Text(detail)
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HTSpacing.md)
        .background(background)
        .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
    }
}

#Preview {
    PersonalizedOutlookCard(outlook: .sample)
        .padding(HTSpacing.screenHorizontal)
        .background(HTColor.surfaceMuted)
}
