import SwiftUI

// MARK: - Primary (`.btn-primary`)

/// Dark filled button: slate-900 background, white text, 44pt minimum height.
struct HTPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var minHeight: CGFloat = HTControlHeight.standard
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htButton)
            .foregroundStyle(.white)
            .padding(.horizontal, HTSpacing.lg)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(configuration.isPressed ? HTColor.brandSubtle : HTColor.brand)
            .clipShape(.rect(cornerRadius: HTRadius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Secondary (`.btn-secondary`)

/// Light filled button: slate-100 background, slate-700 text.
struct HTSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var minHeight: CGFloat = HTControlHeight.standard
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htButton)
            .foregroundStyle(HTColor.textStrong)
            .padding(.horizontal, HTSpacing.lg)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(configuration.isPressed ? HTColor.border : HTColor.surfaceSecondary)
            .clipShape(.rect(cornerRadius: HTRadius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Outline (Quick Add)

/// Full-width outlined button: 2pt slate-900 border, 56pt tall, 16pt radius.
struct HTOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htBodyStrong)
            .foregroundStyle(HTColor.brand)
            .padding(.horizontal, HTSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: HTControlHeight.prominent)
            .background(configuration.isPressed ? HTColor.surfaceSecondary : HTColor.surface)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                    .strokeBorder(HTColor.brand, lineWidth: 2)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Hero buttons (on dark card)

/// White filled button for the hero card's primary action ("Start").
struct HTHeroPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htBodyStrong)
            .foregroundStyle(HTColor.ink)
            .padding(.horizontal, HTSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: HTControlHeight.prominent)
            .background(configuration.isPressed ? HTColor.border : .white)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Translucent button for the hero card's secondary action ("Finish").
struct HTHeroSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htBodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, HTSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: HTControlHeight.prominent)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.1))
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Chip (selectable duration / option)

/// Pill toggle used for duration chips and filter segments.
struct HTChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htCaptionStrong)
            .foregroundStyle(isSelected ? .white : HTColor.textStrong)
            .padding(.horizontal, HTSpacing.md)
            .frame(minHeight: 36)
            .background(isSelected ? HTColor.brand : HTColor.surfaceSecondary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Dot-syntax access

extension ButtonStyle where Self == HTPrimaryButtonStyle {
    static var htPrimary: HTPrimaryButtonStyle { HTPrimaryButtonStyle() }

    static func htPrimary(
        minHeight: CGFloat = HTControlHeight.standard,
        fullWidth: Bool = false
    ) -> HTPrimaryButtonStyle {
        HTPrimaryButtonStyle(minHeight: minHeight, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == HTSecondaryButtonStyle {
    static var htSecondary: HTSecondaryButtonStyle { HTSecondaryButtonStyle() }

    static func htSecondary(
        minHeight: CGFloat = HTControlHeight.standard,
        fullWidth: Bool = false
    ) -> HTSecondaryButtonStyle {
        HTSecondaryButtonStyle(minHeight: minHeight, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == HTOutlineButtonStyle {
    static var htOutline: HTOutlineButtonStyle { HTOutlineButtonStyle() }
}

extension ButtonStyle where Self == HTHeroPrimaryButtonStyle {
    static var htHeroPrimary: HTHeroPrimaryButtonStyle { HTHeroPrimaryButtonStyle() }
}

extension ButtonStyle where Self == HTHeroSecondaryButtonStyle {
    static var htHeroSecondary: HTHeroSecondaryButtonStyle { HTHeroSecondaryButtonStyle() }
}

extension ButtonStyle where Self == HTChipButtonStyle {
    static func htChip(isSelected: Bool) -> HTChipButtonStyle {
        HTChipButtonStyle(isSelected: isSelected)
    }
}

#Preview("Buttons") {
    ScrollView {
        VStack(spacing: HTSpacing.md) {
            Button("Primary") {}
                .buttonStyle(.htPrimary)

            Button("Secondary") {}
                .buttonStyle(.htSecondary)

            Button("Disabled") {}
                .buttonStyle(.htPrimary)
                .disabled(true)

            Button("+ Quick Add") {}
                .buttonStyle(.htOutline)

            HStack(spacing: HTSpacing.md) {
                Button("Start") {}
                    .buttonStyle(.htHeroPrimary)
                Button("Finish") {}
                    .buttonStyle(.htHeroSecondary)
            }
            .htHeroCard()

            HStack(spacing: HTSpacing.sm) {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes)") {}
                        .buttonStyle(.htChip(isSelected: minutes == 30))
                }
            }
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
