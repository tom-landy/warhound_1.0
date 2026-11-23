import SwiftUI

struct SettingsView: View {
    @AppStorage(AccentTheme.storageKey) private var theme: AccentTheme = .orange
    @AppStorage(AccentTheme.matchIconKey) private var matchIcon = false
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 58), spacing: 14)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LogoView(theme: theme)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                        .shadow(color: theme.color.opacity(0.35), radius: 20, y: 6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                        .animation(.easeInOut(duration: 0.25), value: theme)
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AccentTheme.allCases) { option in
                            Swatch(theme: option, selected: option == theme) {
                                withAnimation(.snappy) { theme = option }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Toggle("Match app icon", isOn: $matchIcon)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Changes the icon on your Home Screen too. iOS shows a short confirmation each time it changes.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: theme) { _, new in new.applyIcon(matchIcon) }
            .onChange(of: matchIcon) { _, new in theme.applyIcon(new) }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

private struct Swatch: View {
    let theme: AccentTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.gradient)
                        .frame(width: 44, height: 44)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.black)
                    }
                }
                .padding(4)
                .overlay {
                    Circle().strokeBorder(selected ? theme.color : .clear, lineWidth: 2.5)
                }
                Text(theme.name)
                    .font(.caption2.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Gear button that opens Settings. Apply inside a NavigationStack.
private struct SettingsButton: ViewModifier {
    @State private var shows: Bool

    init(demo: Bool) {
        _shows = State(initialValue: demo && DemoData.isActive && UserDefaults.standard.bool(forKey: "demoSettings"))
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shows = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $shows) { SettingsView() }
    }
}

extension View {
    /// `demo`: this instance may auto-open for screenshots (`-demo -demoSettings YES`).
    func settingsButton(demo: Bool = false) -> some View { modifier(SettingsButton(demo: demo)) }
}
