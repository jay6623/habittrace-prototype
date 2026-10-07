import SwiftUI

/// Small tinted chip showing a task category.
///
/// Colors follow the Plans page mapping in the PWA. Unknown categories,
/// including the legacy "General" default, use the "Other" slate palette.
struct CategoryChip: View {
    let category: String

    var body: some View {
        Text(category)
            .font(.htCaptionStrong)
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, HTSpacing.sm)
            .padding(.vertical, HTSpacing.xs)
            .background(palette.background)
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(palette.ring, lineWidth: 1)
            }
            .lineLimit(1)
    }

    private var palette: ChipPalette {
        CategoryChip.palette(for: category)
    }

    /// Chip colors for a PWA category name.
    static func palette(for category: String) -> ChipPalette {
        switch category.trimmingCharacters(in: .whitespaces).lowercased() {
        case "work": HTColor.Chip.sky
        case "study": HTColor.Chip.violet
        case "chores": HTColor.Chip.amber
        case "fitness/health": HTColor.Chip.emerald
        case "errands/admin": HTColor.Chip.orange
        case "hobbies/leisure": HTColor.Chip.fuchsia
        case "social": HTColor.Chip.cyan
        default: HTColor.Chip.slate
        }
    }
}

#Preview("Category chips") {
    let categories = [
        "Study", "Work", "Chores", "Fitness/Health",
        "Errands/Admin", "Hobbies/Leisure", "Social", "Other", "General",
    ]

    VStack(alignment: .leading, spacing: HTSpacing.sm) {
        ForEach(categories, id: \.self) { category in
            CategoryChip(category: category)
        }
    }
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}
