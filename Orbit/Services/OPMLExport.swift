import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Orbit-Info.plist so .opml files open in the app.
    static let opml = UTType(importedAs: "org.opml.opml", conformingTo: .xml)
}

extension OPML {
    static func export(_ podcasts: [Podcast]) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let lines = podcasts.map {
            "    <outline type=\"rss\" text=\"\(escape($0.title))\" title=\"\(escape($0.title))\" xmlUrl=\"\(escape($0.feedURL.absoluteString))\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Shows I follow in Orbit</title></head>
          <body>
        \(lines.joined(separator: "\n"))
          </body>
        </opml>

        """
    }

    /// Writes the export to a temporary file for the share sheet.
    static func exportFile(_ podcasts: [Podcast]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit Shows.opml")
        do {
            try export(podcasts).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
