import SwiftUI
import WidgetKit

/// Shows the widget layouts at real sizes. Used for screenshots (`-demo -demoWidgets YES`)
/// until the widgets can be switched on with a paid developer account.
struct WidgetGalleryView: View {
    @Environment(\.theme) private var theme

    private var snapshot: WidgetSnapshot {
        var s = WidgetSnapshot.sample
        s.accent = theme.hexValues.base
        return s
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(spacing: 22) {
                    frame(width: 158, height: 158) { NowPlayingWidgetView(snapshot: snapshot, family: .systemSmall) }
                    VStack(spacing: 14) {
                        lockFrame(width: 158, height: 66) { NowPlayingWidgetView(snapshot: snapshot, family: .accessoryRectangular) }
                        lockFrame(width: 66, height: 66, circle: true) { NowPlayingWidgetView(snapshot: snapshot, family: .accessoryCircular) }
                    }
                }
                frame(width: 338, height: 158) { NowPlayingWidgetView(snapshot: snapshot, family: .systemMedium) }
                frame(width: 338, height: 158) { UpNextWidgetView(snapshot: snapshot, family: .systemMedium) }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.08)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Widgets")
    }

    private func frame<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(width: width, height: height)
            .background(LinearGradient(colors: [Color(widgetHex: 0x23262D), Color(widgetHex: 0x0C0D10)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func lockFrame<Content: View>(width: CGFloat, height: CGFloat, circle: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(circle ? 4 : 8)
            .frame(width: width, height: height)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: circle ? 33 : 12, style: .continuous))
            .foregroundStyle(.white)
    }
}
