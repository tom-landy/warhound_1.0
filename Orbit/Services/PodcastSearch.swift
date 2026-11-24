import Foundation

struct SearchResult: Identifiable, Decodable, Hashable, Sendable {
    let collectionId: Int
    let collectionName: String
    let artistName: String?
    let artworkUrl600: URL?
    let feedUrl: URL?
    let primaryGenreName: String?

    var id: Int { collectionId }
}

/// Apple's public podcast directory. No API key needed.
enum PodcastSearch {
    private struct Response: Decodable { let results: [SearchResult] }

    static func search(_ term: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "media", value: "podcast"),
            .init(name: "entity", value: "podcast"),
            .init(name: "limit", value: "30"),
            .init(name: "term", value: term),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(Response.self, from: data).results.filter { $0.feedUrl != nil }
    }

    /// Artwork for a feed that has none of its own, matched by show name.
    /// Private feeds are usually named after their public show ("Upgrade+ — Private").
    static func artworkFallback(for title: String) async -> URL? {
        let cleaned = title
            .replacingOccurrences(of: "\\s*[—–-]\\s*Private.*$", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\b(Plus|Premium|Members?|Bonus Feed|Ad[- ]Free)\\b|\\+", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard cleaned.count > 2, let results = try? await search(cleaned) else { return nil }
        let wanted = normalise(cleaned)
        let match = results.first { normalise($0.collectionName) == wanted }
            ?? results.first { normalise($0.collectionName).hasPrefix(wanted) || wanted.hasPrefix(normalise($0.collectionName)) }
        return match?.artworkUrl600
    }

    private static func normalise(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
