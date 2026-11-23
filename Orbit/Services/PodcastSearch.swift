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
}
