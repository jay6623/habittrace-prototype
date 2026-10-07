import SwiftUI

/// One tile in the Today stats grid: eyebrow label over a large value.
///
/// Matches `rounded-2xl border bg-white p-4`. The `.attention` style
/// reproduces the rose tint the PWA applies to the Unlogged tile when
/// its count is above zero.
struct HTStatTile: View {
    enum Style {
        case neutral
        case attention
    }

    let title: String
    let value: String
    var caption: String?
    var style: Style = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            HTEyebrowLabel(text: title, color: labelColor)

            Text(value)
                .font(.htStatValue)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let caption {
                Text(caption)
                    .font(.htCaption)
                    .foregroundStyle(labelColor)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(background: background)
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch style {
        case .neutral: HTColor.surface
        case .attention: HTColor.danger50
        }
    }

    private var labelColor: Color {
        switch style {
        case .neutral: HTColor.textMuted
        case .attention: HTColor.danger700
        }
    }

    private var valueColor: Color {
        switch style {
        case .neutral: HTColor.textPrimary
        case .attention: HTColor.danger700
        }
    }
}

#Preview("Stat tiles") {
    LazyVGrid(
        columns: [
            GridItem(.flexible(), spacing: HTSpacing.md),
            GridItem(.flexible(), spacing: HTSpacing.md),
        ],
        spacing: HTSpacing.md
    ) {
        HTStatTile(title: "Completed", value: "3")
        HTStatTile(title: "Remaining", value: "5")
        HTStatTile(title: "Planned", value: "240", caption: "minutes")
        HTStatTile(title: "Unlogged", value: "2", caption: "Tap to review", style: .attention)
    }
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}
