import SwiftUI

/// The PWA's "How long?" control: preset chips plus a Custom minutes field.
/// Writes into a `PlanDraft`'s duration.
struct DurationChips: View {
    @Binding var durationMinutes: Int
    @Binding var usesCustom: Bool
    @Binding var customText: String

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HTSpacing.sm) {
                    ForEach(PlanDraft.durationPresets, id: \.self) { minutes in
                        let isSelected = !usesCustom && durationMinutes == minutes
                        Button("\(minutes)m") {
                            usesCustom = false
                            customText = ""
                            durationMinutes = minutes
                        }
                        .buttonStyle(.htChip(isSelected: isSelected))
                        .accessibilityLabel("\(minutes) minutes")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }

                    Button("Custom") {
                        usesCustom = true
                        customText = String(durationMinutes)
                    }
                    .buttonStyle(.htChip(isSelected: usesCustom))
                    .accessibilityAddTraits(usesCustom ? [.isSelected] : [])
                }
                .padding(.vertical, HTSpacing.xs)
            }
            .scrollClipDisabled()

            if usesCustom {
                HStack {
                    TextField("Minutes", text: $customText)
                        .keyboardType(.numberPad)
                        .onChange(of: customText) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(3))
                            if digits != value {
                                customText = digits
                                return
                            }
                            durationMinutes = Int(digits) ?? 0
                        }

                    Text("min")
                        .foregroundStyle(HTColor.textMuted)
                }
            }
        }
    }

    /// Whether the Custom field is selected but empty.
    static func customMissing(usesCustom: Bool, customText: String) -> Bool {
        usesCustom && customText.isEmpty
    }
}
