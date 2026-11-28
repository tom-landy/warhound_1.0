import SwiftUI

/// Episode notes, laid out for reading: a little larger than body text, paragraphs and list
/// items spaced apart, and bullets with a hanging indent so wrapped lines line up.
struct NotesText: View {
    let notes: AttributedString
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.45) {
            ForEach(Array(Self.paragraphs(notes).enumerated()), id: \.offset) { _, paragraph in
                line(paragraph.text)
                    .padding(.top, paragraph.gapBefore ? size * 0.6 : 0)
            }
        }
        .font(.system(size: size))
        .lineSpacing(size * 0.2)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func line(_ text: AttributedString) -> some View {
        let plain = String(text.characters)
        if plain.hasPrefix("• ") {
            bullet("•", Self.drop(2, from: text), indent: 0)
        } else if plain.hasPrefix("\u{2003}◦ ") {
            bullet("◦", Self.drop(3, from: text), indent: size)
        } else {
            Text(text)
        }
    }

    private func bullet(_ mark: String, _ text: AttributedString, indent: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
            Text(mark).foregroundStyle(.secondary)
            Text(text)
        }
        .padding(.leading, indent)
    }

    private static func drop(_ count: Int, from text: AttributedString) -> AttributedString {
        let start = text.characters.index(text.startIndex, offsetBy: min(count, text.characters.count))
        return AttributedString(text[start...])
    }

    /// Splits on line breaks. Blank lines become extra space before the next paragraph.
    static func paragraphs(_ text: AttributedString) -> [(text: AttributedString, gapBefore: Bool)] {
        var out: [(text: AttributedString, gapBefore: Bool)] = []
        var gap = false
        var start = text.startIndex
        var index = text.startIndex
        func flush(_ end: AttributedString.Index) {
            let piece = AttributedString(text[start..<end])
            if piece.characters.allSatisfy(\.isWhitespace) {
                if !out.isEmpty { gap = true }
            } else {
                out.append((piece, gap))
                gap = false
            }
        }
        while index < text.endIndex {
            if text.characters[index] == "\n" {
                flush(index)
                start = text.characters.index(after: index)
            }
            index = text.characters.index(after: index)
        }
        flush(text.endIndex)
        return out
    }
}
