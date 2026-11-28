import Foundation

// Show notes: kept as light markdown so links keep their text and stay tappable,
// and timestamps become links that jump to that point in the episode.

extension String {
    /// Markdown notes rendered for display: links tappable, bare web addresses linked, and
    /// timestamps (12:34 or 1:02:03) linked to `orbit-seek://<seconds>`.
    var notesAttributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: self, options: options)) ?? AttributedString(self)
        let plain = String(result.characters)
        let range = NSRange(plain.startIndex..., in: plain)

        func addLink(_ url: URL, at nsRange: NSRange) {
            guard let r = Range(nsRange, in: plain),
                  let lower = AttributedString.Index(r.lowerBound, within: result),
                  let upper = AttributedString.Index(r.upperBound, within: result),
                  result[lower..<upper].runs.allSatisfy({ $0.link == nil }) else { return }
            result[lower..<upper].link = url
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: plain, range: range) {
                if let url = match.url { addLink(url, at: match.range) }
            }
        }
        if let stamp = try? NSRegularExpression(pattern: "(?<![\\d:])(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})(?![\\d:])") {
            let ns = plain as NSString
            for match in stamp.matches(in: plain, range: range) {
                let hours = match.range(at: 1).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 1))) ?? 0
                let minutes = Int(ns.substring(with: match.range(at: 2))) ?? 0
                let seconds = Int(ns.substring(with: match.range(at: 3))) ?? 0
                guard seconds < 60, hours > 0 || minutes < 600 else { continue }
                if let url = URL(string: "orbit-seek://\(hours * 3600 + minutes * 60 + seconds)") {
                    addLink(url, at: match.range)
                }
            }
        }
        return result
    }
}

extension Episode {
    /// What the notes screens show: full notes when the feed gave them, else the summary.
    var notesDisplay: AttributedString {
        let source = notes.isEmpty ? summary : notes
        return source.isEmpty ? AttributedString("No episode notes.") : source.notesAttributed
    }

    /// Seconds from an `orbit-seek://` link in the notes.
    static func seekSeconds(from url: URL) -> TimeInterval? {
        guard url.scheme == "orbit-seek", let host = url.host() else { return nil }
        return TimeInterval(host)
    }
}
