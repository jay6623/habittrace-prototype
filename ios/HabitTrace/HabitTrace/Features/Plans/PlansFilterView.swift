import SwiftUI

/// Status chips plus the PWA's category and priority menus. Changing a
/// selection only updates the bound values; filtering happens in the
/// view model.
struct PlansFilterView: View {
    @Binding var selection: PlansFilter
    @Binding var category: TaskCategory?
    @Binding var priority: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HTSpacing.sm) {
                    ForEach(PlansFilter.allCases) { filter in
                        Button(filter.title) {
                            selection = filter
                        }
                        .buttonStyle(.htChip(isSelected: selection == filter))
                        .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter plans by status")

            HStack(spacing: HTSpacing.sm) {
                Menu {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(TaskCategory?.none)
                        ForEach(TaskCategory.allCases) { item in
                            Text(item.rawValue).tag(TaskCategory?.some(item))
                        }
                    }
                } label: {
                    filterMenuLabel(category?.rawValue ?? "All categories", isActive: category != nil)
                }
                .accessibilityLabel("Filter plans by category")

                Menu {
                    Picker("Priority", selection: $priority) {
                        Text("All priorities").tag(Int?.none)
                        ForEach(1...5, id: \.self) { level in
                            Text(Self.priorityLabel(level)).tag(Int?.some(level))
                        }
                    }
                } label: {
                    filterMenuLabel(priority.map(Self.priorityLabel) ?? "All priorities", isActive: priority != nil)
                }
                .accessibilityLabel("Filter plans by priority")
            }
        }
    }

    private func filterMenuLabel(_ text: String, isActive: Bool) -> some View {
        HStack(spacing: HTSpacing.xs) {
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .font(.htCaptionStrong)
        .foregroundStyle(isActive ? .white : HTColor.textStrong)
        .padding(.horizontal, HTSpacing.md)
        .frame(minHeight: 36)
        .background(isActive ? HTColor.brand : HTColor.surfaceSecondary)
        .clipShape(Capsule())
    }

    nonisolated static func priorityLabel(_ level: Int) -> String {
        switch level {
        case 1: "1 — Low"
        case 5: "5 — High"
        default: "\(level)"
        }
    }
}

#Preview {
    @Previewable @State var selection: PlansFilter = .inProgress
    @Previewable @State var category: TaskCategory? = .work
    @Previewable @State var priority: Int? = nil

    PlansFilterView(selection: $selection, category: $category, priority: $priority)
        .padding(HTSpacing.screenHorizontal)
        .background(HTColor.surfaceMuted)
}
