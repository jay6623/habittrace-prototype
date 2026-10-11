import SwiftUI

/// Title, add button, and day navigation for the Plans screen.
///
/// Renders the view model's selected date; it keeps no date state of
/// its own.
struct PlansHeader: View {
    let selectedDate: Date
    let isShowingToday: Bool
    let isLoading: Bool

    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    let onPickDate: () -> Void
    let onAddPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text("Plans")
                        .htPageTitle()

                    Text("Make room for what matters today.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textSecondary)
                }

                Spacer(minLength: HTSpacing.sm)

                Button {
                    onAddPlan()
                } label: {
                    Label("Add plan", systemImage: "plus")
                }
                .buttonStyle(.htPrimary)
            }

            dayNavigator
        }
    }

    private var dayNavigator: some View {
        HStack(spacing: HTSpacing.xs) {
            stepButton(systemImage: "chevron.left", label: "Previous day", action: onPrevious)

            Button {
                onPickDate()
            } label: {
                VStack(spacing: 2) {
                    Text(dateTitle)
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)

                    Text(dateSubtitle)
                        .font(.htCaption)
                        .foregroundStyle(isShowingToday ? HTColor.success700 : HTColor.textMuted)
                }
                .frame(maxWidth: .infinity, minHeight: HTControlHeight.standard)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change date")
            .accessibilityValue(dateTitle)
            .accessibilityHint("Opens a calendar")

            stepButton(systemImage: "chevron.right", label: "Next day", action: onNext)

            if !isShowingToday {
                Button("Today") {
                    onToday()
                }
                .buttonStyle(.htSecondary)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, HTSpacing.xs)
                    .accessibilityLabel("Loading plans")
            }
        }
        .htCard(padding: HTSpacing.xs)
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(HTColor.textStrong)
                .frame(width: HTControlHeight.standard, height: HTControlHeight.standard)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var dateTitle: String {
        selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var dateSubtitle: String {
        if isShowingToday {
            return "Today"
        }
        return selectedDate.formatted(.dateTime.year())
    }
}

#Preview("Today") {
    PlansHeader(
        selectedDate: .now,
        isShowingToday: true,
        isLoading: false,
        onPrevious: {}, onNext: {}, onToday: {}, onPickDate: {}, onAddPlan: {}
    )
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}

#Preview("Other day, loading") {
    PlansHeader(
        selectedDate: .now.addingTimeInterval(-86_400 * 3),
        isShowingToday: false,
        isLoading: true,
        onPrevious: {}, onNext: {}, onToday: {}, onPickDate: {}, onAddPlan: {}
    )
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}
