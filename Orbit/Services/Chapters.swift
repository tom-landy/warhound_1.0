import Foundation

// Foundation only, so tools/feedcheck can compile it outside the app.

struct Chapter: Codable, Hashable, Sendable {
    var start: Double
    var title: String
    var url: URL?
}

/// Reads chapters from a Podcasting 2.0 chapters file (JSON) or from ID3 CHAP frames
/// at the start of an MP3, which is what ATP and Relay shows use.
enum Chapters {
    static func load(audio: URL, localFile: URL?, chaptersURL: URL?) async -> [Chapter] {
        if let chaptersURL, let (data, _) = try? await URLSession.shared.data(from: chaptersURL) {
            let chapters = fromJSON(data)
            if !chapters.isEmpty { return chapters }
        }
        if let localFile, let data = readLocalID3(localFile) {
            return fromID3(data)
        }
        if let data = try? await readRemoteID3(audio) {
            return fromID3(data)
        }
        return []
    }

    // MARK: - JSON chapters

    static func fromJSON(_ data: Data) -> [Chapter] {
        struct File: Decodable {
            struct Item: Decodable {
                let startTime: Double
                let title: String?
                let url: String?
                let toc: Bool?
            }
            let chapters: [Item]
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.chapters
            .filter { $0.toc != false }
            .map { Chapter(start: $0.startTime, title: $0.title ?? "", url: $0.url.flatMap(URL.init(string:))) }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Reading the ID3 tag

    /// Fetches only the ID3 tag at the start of the file, never the whole episode.
    static func readRemoteID3(_ url: URL, limit: Int = 6_000_000) async throws -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("bytes=0-\(limit)", forHTTPHeaderField: "Range")
        request.setValue("Orbit/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        var data = Data()
        data.reserveCapacity(65_536)
        var needed = 10
        for try await byte in bytes {
            data.append(byte)
            if data.count == 10 {
                guard let size = tagSize(data) else { return nil }
                needed = min(size, limit)
            }
            if data.count >= needed { break }
        }
        return data
    }

    static func readLocalID3(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10), let size = tagSize(header) else { return nil }
        let rest = (try? handle.read(upToCount: size - 10)) ?? Data()
        return header + rest
    }

    /// Total tag length including the 10-byte header, or nil if there's no ID3v2 tag.
    static func tagSize(_ header: Data) -> Int? {
        let b = [UInt8](header.prefix(10))
        guard b.count == 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 else { return nil }
        let footer = b[5] & 0x10 != 0 ? 10 : 0
        return 10 + syncsafe(b, 6) + footer
    }

    // MARK: - Parsing ID3 CHAP frames

    static func fromID3(_ data: Data) -> [Chapter] {
        let b = [UInt8](data)
        guard let size = tagSize(data) else { return [] }
        let version = b[3]
        guard version == 3 || version == 4 else { return [] }
        let end = min(b.count, size)
        var start = 10
        if b[5] & 0x40 != 0, start + 4 <= end {
            // Extended header
            let ext = version == 4 ? syncsafe(b, start) : be32(b, start) + 4
            start += ext
        }
        var chapters: [Chapter] = []
        for frame in frames(b, from: start, to: end, version: version) where frame.id == "CHAP" {
            if let chapter = chapter(b, frame.body, version: version) { chapters.append(chapter) }
        }
        return chapters.sorted { $0.start < $1.start }
    }

    private struct Frame {
        let id: String
        let body: Range<Int>
    }

    private static func frames(_ b: [UInt8], from start: Int, to end: Int, version: UInt8) -> [Frame] {
        var out: [Frame] = []
        var i = start
        while i + 10 <= end {
            guard b[i] != 0 else { break } // padding
            let id = String(decoding: b[i..<(i + 4)], as: UTF8.self)
            var size = version == 4 ? syncsafe(b, i + 4) : be32(b, i + 4)
            // Some encoders write plain sizes in v2.4 tags.
            if version == 4, i + 10 + size > end || !looksLikeFrame(b, i + 10 + size, end) {
                let plain = be32(b, i + 4)
                if i + 10 + plain <= end, looksLikeFrame(b, i + 10 + plain, end) { size = plain }
            }
            let bodyStart = i + 10
            guard size > 0, bodyStart + size <= end else { break }
            out.append(Frame(id: id, body: bodyStart..<(bodyStart + size)))
            i = bodyStart + size
        }
        return out
    }

    private static func looksLikeFrame(_ b: [UInt8], _ i: Int, _ end: Int) -> Bool {
        if i >= end { return true }
        if b[i] == 0 { return true }
        guard i + 4 <= end else { return false }
        return b[i..<(i + 4)].allSatisfy { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) }
    }

    private static func chapter(_ b: [UInt8], _ body: Range<Int>, version: UInt8) -> Chapter? {
        var i = body.lowerBound
        while i < body.upperBound && b[i] != 0 { i += 1 } // element ID
        i += 1
        guard i + 16 <= body.upperBound else { return nil }
        let startMs = be32(b, i)
        i += 16
        var title = ""
        var url: URL?
        for sub in frames(b, from: i, to: body.upperBound, version: version) {
            switch sub.id {
            case "TIT2": title = text(b, sub.body)
            case "WXXX": url = linkURL(b, sub.body)
            default: break
            }
        }
        return Chapter(start: Double(startMs) / 1000, title: title, url: url)
    }

    private static func text(_ b: [UInt8], _ r: Range<Int>) -> String {
        guard r.count > 1 else { return "" }
        let s = decode(Data(b[(r.lowerBound + 1)..<r.upperBound]), encoding: b[r.lowerBound])
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}")))
    }

    private static func linkURL(_ b: [UInt8], _ r: Range<Int>) -> URL? {
        guard r.count > 2 else { return nil }
        let encoding = b[r.lowerBound]
        var i = r.lowerBound + 1
        // Skip the description, which ends with one zero byte (or two for UTF-16).
        if encoding == 1 || encoding == 2 {
            while i + 1 < r.upperBound && !(b[i] == 0 && b[i + 1] == 0) { i += 2 }
            i += 2
        } else {
            while i < r.upperBound && b[i] != 0 { i += 1 }
            i += 1
        }
        guard i < r.upperBound else { return nil }
        let raw = String(decoding: b[i..<r.upperBound], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0} "))
        return URL(string: raw)
    }

    private static func decode(_ data: Data, encoding: UInt8) -> String {
        switch encoding {
        case 0: return String(data: data, encoding: .isoLatin1) ?? ""
        case 1: return String(data: data, encoding: .utf16) ?? ""
        case 2: return String(data: data, encoding: .utf16BigEndian) ?? ""
        default: return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }
    }

    private static func syncsafe(_ b: [UInt8], _ i: Int) -> Int {
        (Int(b[i]) & 0x7F) << 21 | (Int(b[i + 1]) & 0x7F) << 14 | (Int(b[i + 2]) & 0x7F) << 7 | (Int(b[i + 3]) & 0x7F)
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
}
