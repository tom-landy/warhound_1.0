import SwiftUI

extension TimeInterval {
    /// 1:02:03 or 12:34
    var clock: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let t = Int(self)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1 hr 5 min" or "42 min"
    var spoken: String {
        guard isFinite, self > 0 else { return "" }
        let mins = Int((self / 60).rounded())
        if mins < 60 { return "\(max(1, mins)) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

extension Date {
    var episodeDate: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        if self > .now.addingTimeInterval(-6 * 86400) { return formatted(.dateTime.weekday(.wide)) }
        if Calendar.current.isDate(self, equalTo: .now, toGranularity: .year) {
            return formatted(.dateTime.day().month(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }
}

struct ArtworkView: View {
    let url: URL?
    var seed: String = ""
    var cornerRadius: CGFloat = 10
    @Environment(\.displayScale) private var displayScale

    /// Stable colour per show so placeholders don't all look the same.
    private var hue: Double {
        Double(seed.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value } % 360) / 360
    }

    var body: some View {
        // A fixed square; the image is fitted inside it so wide or tall artwork is never
        // cropped or stretched. (No blur behind it: blurs make scrolling lists stutter.)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    CachedArtwork(url: url, pixels: ArtworkCache.bucket(proxy.size.width * displayScale)) {
                        ZStack {
                            LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.45),
                                                    Color(hue: hue, saturation: 0.6, brightness: 0.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "waveform")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

/// Shows downsized, cached artwork: instantly if it's in memory, otherwise loaded off the main
/// thread with a short fade. Replaces AsyncImage, which re-decoded full-size covers on scroll.
private struct CachedArtwork<Placeholder: View>: View {
    let url: URL?
    let pixels: Int
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: (key: String, image: UIImage)?

    private var key: String { "\(url?.absoluteString ?? "")#\(pixels)" }

    var body: some View {
        let image = loaded?.key == key ? loaded?.image : url.flatMap { ArtworkCache.shared.cached($0, size: pixels) }
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            guard let url, loaded?.key != key, ArtworkCache.shared.cached(url, size: pixels) == nil else { return }
            let size = pixels
            let fetched = await Task.detached(priority: .userInitiated) {
                await ArtworkCache.shared.image(url, size: size)
            }.value
            guard let fetched, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { loaded = (key, fetched) }
        }
    }
}
