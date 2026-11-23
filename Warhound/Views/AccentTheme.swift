import SwiftUI
import UIKit

/// App colour themes. Keep in sync with design/themes.json, which renders the matching icons.
enum AccentTheme: String, CaseIterable, Identifiable {
    case orange, ember, gold, lime, mint, teal, blue, violet, pink, silver

    static let storageKey = "accentTheme"
    static let matchIconKey = "matchAppIcon"

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var color: Color { Color(hex: hex.base) }
    var top: Color { Color(hex: hex.top) }
    var bottom: Color { Color(hex: hex.bottom) }
    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// nil means the primary icon (orange).
    var iconName: String? { self == .orange ? nil : "AppIcon-\(rawValue)" }

    private var hex: (base: UInt32, top: UInt32, bottom: UInt32) {
        switch self {
        case .orange: (0xF26A2A, 0xFFB25C, 0xF2551D)
        case .ember: (0xEC4A3C, 0xFF8A6B, 0xD92D2D)
        case .gold: (0xF5B83D, 0xFFE08A, 0xEE9F1A)
        case .lime: (0x8FD14F, 0xD4F27A, 0x5DB82E)
        case .mint: (0x3DD39A, 0x8FF5C8, 0x1FAF7A)
        case .teal: (0x2CC2D4, 0x86ECF0, 0x1497B0)
        case .blue: (0x4D8DFF, 0x9CCBFF, 0x2F6BF0)
        case .violet: (0xA57DFF, 0xD3B5FF, 0x7A4AF0)
        case .pink: (0xFF6AA5, 0xFFA8CB, 0xEE3D82)
        case .silver: (0xD4D7DE, 0xFFFFFF, 0x9EA2AD)
        }
    }

    @MainActor
    func applyIcon(_ match: Bool) {
        let wanted = match ? iconName : nil
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != wanted else { return }
        UIApplication.shared.setAlternateIconName(wanted)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AccentTheme = .orange
}

extension EnvironmentValues {
    var theme: AccentTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// The Warhound mark drawn natively, so it takes the current theme colour.
struct LogoView: View {
    var theme: AccentTheme
    var showsBackground = true

    private struct Bar { let x, y, w, h, opacity: Double }
    private static let bars = [
        Bar(x: 148, y: 452, w: 56, h: 120, opacity: 0.55),
        Bar(x: 820, y: 452, w: 56, h: 120, opacity: 0.55),
        Bar(x: 60, y: 482, w: 40, h: 60, opacity: 0.25),
        Bar(x: 924, y: 482, w: 40, h: 60, opacity: 0.25),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 1024
            ZStack {
                if showsBackground {
                    LinearGradient(colors: [Color(hex: 0x23262D), Color(hex: 0x0C0D10)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [theme.bottom.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.55),
                                   startRadius: 0, endRadius: 512 * s)
                }
                Path { p in
                    p.move(to: CGPoint(x: 292 * s, y: 340 * s))
                    p.addLine(to: CGPoint(x: 400 * s, y: 700 * s))
                    p.addLine(to: CGPoint(x: 512 * s, y: 430 * s))
                    p.addLine(to: CGPoint(x: 624 * s, y: 700 * s))
                    p.addLine(to: CGPoint(x: 732 * s, y: 340 * s))
                }
                .stroke(theme.gradient, style: StrokeStyle(lineWidth: 88 * s, lineCap: .round, lineJoin: .round))
                ForEach(Self.bars, id: \.x) { bar in
                    Capsule()
                        .fill(theme.gradient)
                        .opacity(bar.opacity)
                        .frame(width: bar.w * s, height: bar.h * s)
                        .position(x: (bar.x + bar.w / 2) * s, y: (bar.y + bar.h / 2) * s)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
