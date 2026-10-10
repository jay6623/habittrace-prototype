import SwiftUI

/// Date line over a "Today, Name" title, matching the PWA mobile header.
struct TodayHeader: View {
    let date: Date
    var name: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(TaskTimeFormatting.headerDate(date))
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)

            Text(title)
                .htPageTitle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let name, !name.isEmpty {
            return "Today, \(name)"
        }
        return "Today"
    }
}

#Preview {
    VStack(spacing: HTSpacing.xl) {
        TodayHeader(date: .now, name: "Yen")
        TodayHeader(date: .now)
    }
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}
