import SwiftUI

/// First launch: choose appearance. Shown once; changeable later in Settings.
struct WelcomeView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppAppearance.chosenKey) private var chosen = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            LogoView(theme: theme)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(spacing: 8) {
                Text("Welcome to Orbit")
                    .font(.largeTitle.bold())
                Text("Choose how Orbit looks. You can change this later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                ForEach(AppAppearance.allCases) { option in
                    AppearanceCard(option: option, selected: option == appearance) {
                        withAnimation(.easeInOut(duration: 0.2)) { appearance = option }
                    }
                }
            }
            Spacer()
            Button {
                chosen = true
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AccentTheme.onColor)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}

struct AppearanceCard: View {
    let option: AppAppearance
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? theme.color : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1)
                    }
                Label(option.name, systemImage: option.symbol)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch option {
        case .light: MiniScreen(dark: false)
        case .dark: MiniScreen(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniScreen(dark: false)
                MiniScreen(dark: true)
            }
        }
    }
}

/// A tiny sketch of the Latest screen in light or dark.
private struct MiniScreen: View {
    let dark: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let background = dark ? Color(white: 0.08) : Color(white: 0.97)
        let ink = dark ? Color(white: 0.85) : Color(white: 0.2)
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(ink).frame(width: 30, height: 6)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.color).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.8)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.4)).frame(width: 18, height: 3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
