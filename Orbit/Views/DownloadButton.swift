import SwiftUI

/// Download control shown on each episode: download, progress (tap to stop), done, or retry.
struct DownloadButton: View {
    let episode: Episode
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.theme) private var theme

    var body: some View {
        let state = downloads.state(episode)
        Button {
            switch state {
            case .none, .failed: downloads.download(episode)
            case .downloading: downloads.cancel(episode)
            case .downloaded: break
            }
        } label: {
            icon(state)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if state == .downloaded {
                Button(role: .destructive) { downloads.remove(episode) } label: {
                    Label("Remove Download", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(label(state))
    }

    @ViewBuilder private func icon(_ state: DownloadManager.State) -> some View {
        switch state {
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.orange)
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(theme.color)
        case .downloading(let fraction):
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(0.03, fraction))
                        .stroke(theme.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: fraction)
                } else {
                    WaitingArc(color: theme.color)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.color)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 22, height: 22)
        }
    }

    private func label(_ state: DownloadManager.State) -> String {
        switch state {
        case .none: "Download"
        case .failed: "Download failed. Retry."
        case .downloaded: "Downloaded"
        case .downloading(let f): f.map { "Downloading, \(Int($0 * 100)) percent. Tap to stop" } ?? "Waiting to download. Tap to stop"
        }
    }
}

/// Spinning arc for downloads that are queued or waiting for signal.
private struct WaitingArc: View {
    let color: Color
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}
