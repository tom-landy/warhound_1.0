import Foundation

// Show notes: kept as light markdown so links keep their text and stay tappable,
// and timestamps become links that jump to that point in the episode.

extension String {
    /// Feed HTML to light markdown: `<a href>` becomes `[text](url)`, list items become bullets,
    /// paragraphs become lines; everything else is stripped like `plainText`.
    var notesMarkdown: String {
        guard let anchor = try? NSRegularExpression(
            pattern: "<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return plainText }
        let ns = self as NSString
        var out = ""
        var last = 0
        for match in anchor.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let url = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: " ", with: "%20")
                .replacingOccurrences(of: ")", with: "%29")
            var text = ns.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[", with: "(")
                .replacingOccurrences(of: "]", with: ")")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = url }
            out += "[\(text)](\(url))"
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
            .replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</?(ul|ol)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .plainText
    }

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
