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

    var hexValues: (base: UInt32, top: UInt32, bottom: UInt32) { hex }

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

/// The Orbit mark drawn natively, so it takes the current theme colour.
/// Geometry matches design/logo-template.svg on a 1024 grid.
struct LogoView: View {
    var theme: AccentTheme
    var showsBackground = true

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 1024
            ZStack {
                if showsBackground {
                    LinearGradient(colors: [Color(hex: 0x23262D), Color(hex: 0x0C0D10)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [theme.bottom.opacity(0.22), .clear], center: .center,
                                   startRadius: 0, endRadius: 512 * s)
                }
                Self.mark(scale: s).fill(theme.gradient)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Open ring (gap of 68° at upper right), satellite in the gap, core in the middle.
    static func mark(scale s: CGFloat) -> Path {
        let c = 512.0, r = 250.0
        var ring = Path()
        let steps = 120
        for i in 0...steps {
            let degrees = -11 + 292 * Double(i) / Double(steps)
            let a = degrees * .pi / 180
            let point = CGPoint(x: (c + r * cos(a)) * s, y: (c + r * sin(a)) * s)
            if i == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
        }
        var shape = ring.strokedPath(StrokeStyle(lineWidth: 92 * s, lineCap: .round, lineJoin: .round))
        shape.addEllipse(in: CGRect(x: (689 - 58) * s, y: (335 - 58) * s, width: 116 * s, height: 116 * s))
        shape.addEllipse(in: CGRect(x: (512 - 74) * s, y: (512 - 74) * s, width: 148 * s, height: 148 * s))
        return shape
    }
}
