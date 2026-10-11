import SwiftUI

/// Horizontal chip row for `PlansFilter`. Changing the selection only
/// updates the bound value; filtering happens in the view model.
struct PlansFilterView: View {
    @Binding var selection: PlansFilter

    var body: some View {
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
    }
}

#Preview {
    @Previewable @State var selection: PlansFilter = .inProgress

    PlansFilterView(selection: $selection)
        .padding(HTSpacing.screenHorizontal)
        .background(HTColor.surfaceMuted)
}
