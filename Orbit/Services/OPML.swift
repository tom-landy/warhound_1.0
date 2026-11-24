import Foundation

// Foundation only, so tools/feedcheck can compile it outside the app.

struct OPMLFeed: Hashable, Sendable {
    let title: String
    let url: URL
}

/// OPML is the subscription list format every podcast app exports.
enum OPML {
    static func parse(_ data: Data) throws -> [OPMLFeed] {
        let delegate = OPMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? FeedError.notAFeed }
        var seen = Set<URL>()
        return delegate.feeds.filter { seen.insert($0.url).inserted }
    }
}

private final class OPMLParser: NSObject, XMLParserDelegate {
    var feeds: [OPMLFeed] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard name.lowercased() == "outline" else { return }
        // Apps disagree on attribute case (xmlUrl, xmlURL, xmlurl).
        let attrs = Dictionary(attributes.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        guard let raw = attrs["xmlurl"]?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return }
        feeds.append(OPMLFeed(title: attrs["title"] ?? attrs["text"] ?? url.host() ?? raw, url: url))
    }
}
