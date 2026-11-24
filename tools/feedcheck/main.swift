// Runs the app's own feed and OPML parsers against real feeds.
// Built and run by CI (see .github/workflows/ios.yml):
//   swiftc -O Orbit/Services/FeedParser.swift Orbit/Services/OPML.swift Orbit/Services/Chapters.swift tools/feedcheck/main.swift -o feedcheck
//   ./feedcheck tools/feedcheck/overcast-sample.opml
import Foundation

let args = CommandLine.arguments
guard args.count > 1, let opmlData = FileManager.default.contents(atPath: args[1]) else {
    print("usage: feedcheck file.opml"); exit(2)
}

let feeds: [OPMLFeed]
do {
    feeds = try OPML.parse(opmlData)
} catch {
    print("FAIL OPML parse: \(error)"); exit(1)
}
print("OPML: \(feeds.count) feeds")
for f in feeds { print("  - \(f.title)") }

// Private feeds in the sample have their tokens redacted, so skip them.
let checkable = feeds.filter { !$0.url.absoluteString.contains("REDACTED") }
print("\nChecking \(checkable.count) public feeds\n")

var failures = 0
for feed in checkable {
    var request = URLRequest(url: feed.url, timeoutInterval: 30)
    request.setValue("Orbit/1.0", forHTTPHeaderField: "User-Agent")
    do {
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let parsed = try FeedParser.parse(data)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        let items = parsed.items
        let noDate = items.filter { $0.pubDate == nil }.count
        let noDuration = items.filter { $0.duration == 0 }.count
        let dupGuids = items.count - Set(items.map(\.guid)).count
        let emptyTitles = items.filter { $0.title.isEmpty }.count
        var problems: [String] = []
        if items.isEmpty { problems.append("NO EPISODES") }
        if noDate > 0 { problems.append("\(noDate) without date") }
        if noDuration > 0 { problems.append("\(noDuration) without duration") }
        if dupGuids > 0 { problems.append("\(dupGuids) duplicate guids") }
        if emptyTitles > 0 { problems.append("\(emptyTitles) untitled") }
        if parsed.artworkURL == nil { problems.append("no artwork") }
        if parsed.artworkURL?.scheme == "http" { problems.append("artwork over http") }
        let httpAudio = items.filter { $0.audioURL?.scheme == "http" }.count
        if httpAudio > 0 { problems.append("\(httpAudio) episodes with http audio") }
        if parsed.title.isEmpty { problems.append("no title") }
        let flag = problems.isEmpty ? "OK  " : "WARN"
        print("\(flag) \(feed.title.prefix(44).padding(toLength: 44, withPad: " ", startingAt: 0)) HTTP \(status) \(data.count / 1024)KB \(items.count) eps \(ms)ms")
        if !problems.isEmpty { print("       " + problems.joined(separator: ", ")) }
        if let newest = items.compactMap(\.pubDate).max() {
            print("       newest: \(newest.formatted(date: .abbreviated, time: .omitted)), sample duration: \(items.first.map { Int($0.duration) } ?? 0)s")
        }
        if noDate > 0, let raw = items.first(where: { $0.pubDate == nil }) {
            print("       undated example: \(raw.title.prefix(60))")
        }
    } catch {
        failures += 1
        print("FAIL \(feed.title): \(error.localizedDescription)")
    }
}
print("\n\(checkable.count - failures)/\(checkable.count) feeds parsed")

// Chapters: read only the ID3 tag (or chapters file) of each show's newest episode.
print("\nChapters (newest episode):")
for feed in checkable where ["Accidental Tech Podcast", "Connected", "Cortex", "Analog(ue)", "No Such Thing As A Fish"].contains(feed.title) {
    guard let data = try? await URLSession.shared.data(from: feed.url).0,
          let parsed = try? FeedParser.parse(data),
          let newest = parsed.items.max(by: { ($0.pubDate ?? .distantPast) < ($1.pubDate ?? .distantPast) }),
          let audio = newest.audioURL else { print("  \(feed.title): couldn't load"); continue }
    let start = Date()
    let chapters = await Chapters.load(audio: audio, localFile: nil, chaptersURL: newest.chaptersURL)
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    let source = newest.chaptersURL != nil ? "chapters file" : "ID3"
    print("  \(feed.title): \(chapters.count) chapters via \(source) in \(ms)ms")
    for c in chapters.prefix(4) { print("     \(Int(c.start))s  \(c.title)") }
}
exit(failures > checkable.count / 2 ? 1 : 0)
