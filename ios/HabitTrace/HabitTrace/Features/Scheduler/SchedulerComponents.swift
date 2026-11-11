import SwiftUI

/// Hour-and-minute picker bound to an `"HH:mm"` string, as the planning
/// preferences store times. Matches the Settings availability pickers.
struct SchedulerTimePicker: View {
    let label: String
    @Binding var time: String

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(label)
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.textStrong)
            DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var binding: Binding<Date> {
        Binding(
            get: { SchedulerLogic.referenceDate(minutes: PlanningPreferences.minutes(from: time)) },
            set: { time = SchedulerLogic.clock(SchedulerLogic.minutesSinceMidnight($0)) }
        )
    }
}

/// Hour-and-minute picker bound to minutes since midnight.
struct SchedulerMinutePicker: View {
    let label: String
    @Binding var minutes: Int
    var isEnabled = true

    var body: some View {
        DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .disabled(!isEnabled)
    }

    private var binding: Binding<Date> {
        Binding(
            get: { SchedulerLogic.referenceDate(minutes: minutes) },
            set: { minutes = SchedulerLogic.minutesSinceMidnight($0) }
        )
    }
}

/// Rounded pill such as "Estimated success 72%" or "15 min buffer".
struct SchedulerBadge: View {
    let text: String
    var foreground: Color = HTColor.textSecondary
    var background: Color = HTColor.surfaceSecondary

    var body: some View {
        Text(text)
            .font(.htCaptionStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, HTSpacing.md)
            .padding(.vertical, HTSpacing.xs)
            .background(background)
            .clipShape(.capsule)
    }
}

/// Bold label above a form control.
struct SchedulerFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.htBodyStrong)
            .foregroundStyle(HTColor.textStrong)
    }
}

/// Menu picker over a fixed list of integers with a formatted title.
struct SchedulerOptionPicker: View {
    let label: String
    let options: [Int]
    @Binding var selection: Int
    var format: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(label)
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.textStrong)
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(format(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(HTColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Violet and status tones from the PWA scheduler pages that the shared
/// palette does not define.
enum SchedulerPalette {
    static let violet50 = Color(hex: 0xF5F3FF)
    static let violet200 = Color(hex: 0xDDD6FE)
    static let violet600 = Color(hex: 0x7C3AED)
    static let violet700 = Color(hex: 0x6D28D9)
    static let violet800 = Color(hex: 0x5B21B6)
    static let amber800 = Color(hex: 0x92400E)
    static let amber950 = Color(hex: 0x451A03)
    static let emerald800 = Color(hex: 0x065F46)
    static let emerald900 = Color(hex: 0x064E3B)
}
