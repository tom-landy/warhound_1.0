import Foundation

struct ParsedFeed: Sendable {
    var link: URL?
    var title = ""
    var author = ""
    var summary = ""
    var artworkURL: URL?
    var items: [ParsedEpisode] = []
}

struct ParsedEpisode: Sendable {
    var guid = ""
    var title = ""
    var summary = ""
    var pubDate: Date?
    var duration: TimeInterval = 0
    var audioURL: URL?
    var artworkURL: URL?
    var chaptersURL: URL?
    var link: URL?
}

enum FeedError: LocalizedError {
    case notAFeed
    var errorDescription: String? { "This URL isn't a podcast feed." }
}

/// Minimal RSS 2.0 + iTunes namespace parser. Synchronous, call it off the main actor.
final class FeedParser: NSObject, XMLParserDelegate {
    private var feed = ParsedFeed()
    private var item: ParsedEpisode?
    private var stack: [String] = []
    private var text = ""
    private var sawChannel = false
    private var firstItemArtwork: URL?

    static func parse(_ data: Data) throws -> ParsedFeed {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), delegate.sawChannel else {
            throw parser.parserError ?? FeedError.notAFeed
        }
        // Some private feeds only carry artwork on episodes.
        if delegate.feed.artworkURL == nil { delegate.feed.artworkURL = delegate.firstItemArtwork }
        return delegate.feed
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        stack.append(name)
        text = ""
        switch name {
        case "channel":
            sawChannel = true
        case "item":
            item = ParsedEpisode()
        case "enclosure":
            if let url = attributes["url"].flatMap(Self.url) { item?.audioURL = url }
        case "itunes:image", "googleplay:image":
            // iTunes art wins over anything else found.
            if let url = (attributes["href"] ?? attributes["url"]).flatMap(Self.url) { setArtwork(url, preferred: name == "itunes:image") }
        case "podcast:chapters":
            if let url = attributes["url"].flatMap(Self.url) { item?.chaptersURL = url }
        case "media:thumbnail":
            if let url = attributes["url"].flatMap(Self.url) { setArtwork(url, preferred: false) }
        case "media:content":
            let isImage = attributes["medium"] == "image" || (attributes["type"] ?? "").hasPrefix("image/")
            if isImage, let url = attributes["url"].flatMap(Self.url) { setArtwork(url, preferred: false) }
        default:
            break
        }
    }

    private func setArtwork(_ url: URL, preferred: Bool) {
        if item != nil {
            if preferred || item?.artworkURL == nil { item?.artworkURL = url }
            if firstItemArtwork == nil { firstItemArtwork = url }
        } else if preferred || feed.artworkURL == nil {
            feed.artworkURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { stack.removeLast(); text = "" }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last

        if var current = item {
            switch name {
            case "title" where parent == "item": current.title = value
            case "link" where parent == "item": current.link = Self.url(value)
            case "guid": current.guid = value
            case "pubDate": current.pubDate = Self.date(value)
            case "itunes:duration": current.duration = Self.duration(value)
            case "itunes:image" where current.artworkURL == nil:
                // A few feeds put the URL in the element text rather than href.
                if let url = Self.url(value), url.scheme != nil { current.artworkURL = url }
            case "description", "itunes:summary", "content:encoded":
                if current.summary.isEmpty || name == "description" { current.summary = value }
            case "item":
                if current.audioURL != nil {
                    if current.guid.isEmpty { current.guid = current.audioURL!.absoluteString }
                    feed.items.append(current)
                }
                item = nil
                return
            default: break
            }
            item = current
            return
        }

        switch name {
        case "title" where parent == "channel": feed.title = value
        case "link" where parent == "channel": feed.link = Self.url(value)
        case "itunes:author" where parent == "channel": feed.author = value
        case "description" where parent == "channel": feed.summary = value
        case "itunes:summary" where parent == "channel":
            if feed.summary.isEmpty { feed.summary = value }
        case "url" where parent == "image":
            if feed.artworkURL == nil { feed.artworkURL = Self.url(value) }
        case "itunes:image" where feed.artworkURL == nil:
            if let url = Self.url(value), url.scheme != nil { feed.artworkURL = url }
        default: break
        }
    }

    // MARK: - Helpers

    private static func url(_ string: String) -> URL? {
        URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let dateFormatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm:ss Z",
    ].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func date(_ string: String) -> Date? {
        for f in dateFormatters {
            if let d = f.date(from: string) { return d }
        }
        return ISO8601DateFormatter().date(from: string)
    }

    /// Accepts "3600", "59:59" or "1:02:03".
    static func duration(_ string: String) -> TimeInterval {
        let parts = string.split(separator: ":").compactMap { Double($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

extension String {
    /// Strips HTML tags and common entities from feed descriptions.
    var plainText: String {
        var s = replacingOccurrences(of: "<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#8217;": "’", "&#8220;": "“", "&#8221;": "”"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
