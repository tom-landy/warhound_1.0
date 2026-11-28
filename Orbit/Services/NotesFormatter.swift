import Foundation

// Foundation only, so tools/feedcheck can compile it outside the app.

extension String {
    /// Feed show notes (HTML, or plain text) as light markdown for `notesAttributed`.
    /// Paragraphs and headings get their own lines, headings are bold, list items and
    /// Relay-style one-link-per-heading lists become bullets, links keep their text.
    /// Line breaks in the HTML source are just spaces, as in a browser.
    var notesMarkdown: String {
        guard range(of: "<[a-zA-Z/!][^>]*>", options: .regularExpression) != nil else {
            // Plain text: keep its own line breaks.
            return NotesWriter.tidy(NotesWriter.escape(NotesWriter.decodeEntities(self)))
        }
        var writer = NotesWriter()
        writer.write(self)
        return NotesWriter.tidy(writer.out)
    }
}

private struct NotesWriter {
    var out = ""
    private var link: (url: String, text: String)?
    private var headingStart: String.Index?
    private var skipping = 0   // inside <script> or <style>
    private var listDepth = 0

    mutating func write(_ html: String) {
        guard let tokens = try? NSRegularExpression(pattern: "<!--.*?-->|<[^>]*>|[^<]+",
                                                    options: [.dotMatchesLineSeparators]) else { return }
        let ns = html as NSString
        for match in tokens.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if token.hasPrefix("<!--") { continue }
            if token.hasPrefix("<") { tag(token) } else if skipping == 0 { text(token) }
        }
        if let link { out += Self.linkMarkdown(link) }
    }

    private mutating func tag(_ raw: String) {
        let closing = raw.hasPrefix("</")
        guard let nameRange = raw.range(of: "[a-zA-Z][a-zA-Z0-9]*", options: .regularExpression) else { return }
        let name = raw[nameRange].lowercased()
        switch name {
        case "script", "style":
            skipping = max(0, skipping + (closing ? -1 : 1))
        case "a":
            if closing {
                if let link { out += Self.linkMarkdown(link) }
                link = nil
            } else if let href = Self.attribute("href", in: raw) {
                if let open = link { out += Self.linkMarkdown(open) }
                startText()
                link = (href, "")
            }
        case "br":
            if link != nil { link?.text += " " } else { breakLine(1) }
        case "p", "blockquote":
            breakLine(2)
        case "div", "tr", "section", "article", "table":
            breakLine(1)
        case "h1", "h2", "h3", "h4":
            if closing {
                closeHeading()
            } else {
                breakLine(2)
                out += "**"
                headingStart = out.endIndex
            }
        case "h5", "h6", "li":
            // Relay puts each link in its own <h5>: those read best as a list too.
            if !closing {
                breakLine(1)
                // Nested list items: one em space of indent per level, then •, ◦ or ▪.
                let depth = name == "li" ? max(1, min(listDepth, 4)) : 1
                out += String(repeating: "\u{2003}", count: depth - 1) + ["•", "◦", "▪", "▪"][depth - 1] + " "
            } else if name != "li" {
                breakLine(1)
            }
        case "ul", "ol":
            listDepth = max(0, listDepth + (closing ? -1 : 1))
            breakLine(closing && listDepth == 0 ? 2 : 1)
        default:
            break
        }
    }

    private mutating func text(_ raw: String) {
        let text = Self.decodeEntities(raw).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if link != nil {
            link?.text += text
            return
        }
        if out.isEmpty || out.hasSuffix("\n") || out.hasSuffix("• ") || out.hasSuffix("◦ ") || out.hasSuffix("▪ ") || out.hasSuffix("**") && headingStart == out.endIndex {
            let trimmed = text.drop { $0 == " " }
            out += Self.escape(String(trimmed))
        } else {
            out += Self.escape(text)
        }
    }

    /// Before link text at the start of a line, drop the space the HTML source left there.
    private mutating func startText() {
        if out.hasSuffix(" "), out.dropLast().hasSuffix("\n") {
            out.removeLast()
        }
    }

    private mutating func closeHeading() {
        while out.hasSuffix(" ") { out.removeLast() }
        if let start = headingStart, start <= out.endIndex {
            if out[start...].isEmpty {
                out.removeLast(2)   // empty heading: drop the opening **
            } else {
                out += "**"
            }
        }
        headingStart = nil
        breakLine(1)
    }

    /// Ends the current line, leaving at least `count` line breaks (2 = blank line).
    private mutating func breakLine(_ count: Int) {
        if headingStart != nil { closeHeading() }
        while out.hasSuffix(" ") { out.removeLast() }
        guard !out.isEmpty else { return }
        let existing = out.reversed().prefix { $0 == "\n" }.count
        if existing < count { out += String(repeating: "\n", count: count - existing) }
    }

    static func linkMarkdown(_ link: (url: String, text: String)) -> String {
        let url = decodeEntities(link.url).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
        var text = link.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if text.isEmpty { text = URL(string: url)?.host() ?? url }
        guard !url.isEmpty else { return escape(text) }
        return "[\(escape(text))](\(url))"
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }

    /// Stops characters in the notes being read as markdown styling.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if "\\*_`[]<>~".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"),
              let regex = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return text }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                       "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
                                       "rdquo": "”", "ldquo": "“", "bull": "•", "middot": "·", "copy": "©",
                                       "reg": "®", "trade": "™", "eacute": "é", "times": "×"]
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let body = ns.substring(with: match.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else {
                replacement = named[body.lowercased()]
            }
            out += replacement ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Trims each line and allows at most one blank line in a row.
    static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n[ \\t]+", with: "\n", options: .regularExpression)   // em space indents survive
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
