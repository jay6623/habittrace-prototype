import SwiftUI

/// Labeled field with the PWA's slate-100 input styling.
struct AuthField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Text(label)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textStrong)
            field
                .htField()
        }
    }
}

/// Rose or emerald notice box used on the auth screens.
struct AuthNotice: View {
    enum Tone {
        case error
        case success
        case warning
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.htBodyStrong)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HTSpacing.md)
            .background(background)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                    .strokeBorder(ring, lineWidth: 1)
            }
            .accessibilityAddTraits(tone == .error ? [] : .isStaticText)
    }

    private var foreground: Color {
        switch tone {
        case .error: HTColor.danger700
        case .success: HTColor.success700
        case .warning: HTColor.warning700
        }
    }

    private var background: Color {
        switch tone {
        case .error: HTColor.danger50
        case .success: HTColor.success50
        case .warning: HTColor.warning50
        }
    }

    private var ring: Color {
        switch tone {
        case .error: HTColor.danger100
        case .success: HTColor.success100
        case .warning: HTColor.warning100
        }
    }
}

/// The "HT" mark shown above auth forms.
struct AuthLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Text("HT")
            .font(.system(size: size * 0.3, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(HTColor.ink)
            .clipShape(.rect(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: HTColor.borderStrong.opacity(0.6), radius: 12, y: 6)
    }
}

/// Dark full-width button with the Google "G" mark.
struct GoogleButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: HTSpacing.sm) {
                GoogleMark()
                    .frame(width: 20, height: 20)
                Text(title)
            }
        }
        .buttonStyle(.htPrimary(minHeight: HTControlHeight.prominent, fullWidth: true))
        .disabled(isBusy)
    }
}

/// Four-color Google "G", drawn from the same paths as the PWA's SVG.
struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            func path(_ string: String, _ color: Color) {
                var transform = CGAffineTransform(scaleX: scale, y: scale)
                if let cgPath = CGPath.fromSVG(string)?.copy(using: &transform) {
                    context.fill(Path(cgPath), with: .color(color))
                }
            }
            path("M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z", Color(hex: 0x4285F4))
            path("M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z", Color(hex: 0x34A853))
            path("M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z", Color(hex: 0xFBBC05))
            path("M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z", Color(hex: 0xEA4335))
        }
        .accessibilityHidden(true)
    }
}

/// "OR USE EMAIL" divider.
struct AuthDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: HTSpacing.md) {
            Rectangle().fill(HTColor.border).frame(height: 1)
            Text(text)
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.textTertiary)
            Rectangle().fill(HTColor.border).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
