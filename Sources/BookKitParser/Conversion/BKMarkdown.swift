//
//  BKMarkdown.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation

/// A small Markdown to XHTML renderer for books: headings, paragraphs, emphasis, links, images,
/// code, block quotes, lists, tables and rules. Raw HTML is shown as text, never interpreted.
enum BKMarkdown {

    enum Block: Equatable {
        /// Heading text is already rendered inline XHTML.
        case heading(level: Int, html: String, plainText: String)
        case html(String)
    }

    /// Splits the document into blocks; headings are separate so books can be split into chapters.
    static func blocks(from markdown: String) -> [Block] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
        var parser = BlockParser(lines: lines)
        return parser.parse()
    }

    /// Renders a whole document (used for nested content: list items and quotes).
    static func html(from markdown: String) -> String {
        blocks(from: markdown).map { block in
            switch block {
            case let .heading(level, html, _): "<h\(level)>\(html)</h\(level)>"
            case let .html(html): html
            }
        }.joined(separator: "\n")
    }

    // MARK: - Blocks

    private struct BlockParser {
        let lines: [String]
        var index = 0
        var blocks: [Block] = []

        init(lines: [String]) {
            self.lines = lines
        }

        mutating func parse() -> [Block] {
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    index += 1
                } else if let fence = Self.fence(trimmed) {
                    parseFencedCode(fence: fence)
                } else if let heading = Self.atxHeading(trimmed) {
                    blocks.append(.heading(level: heading.level,
                                           html: BKMarkdown.inline(heading.text),
                                           plainText: BKMarkdown.plainText(heading.text)))
                    index += 1
                } else if Self.isRule(trimmed) {
                    blocks.append(.html("<hr/>"))
                    index += 1
                } else if trimmed.hasPrefix(">") {
                    parseQuote()
                } else if Self.listMarker(line) != nil {
                    parseList()
                } else if line.hasPrefix("    ") {
                    parseIndentedCode()
                } else if Self.isTableStart(at: index, in: lines) {
                    parseTable()
                } else {
                    parseParagraph()
                }
            }
            return blocks
        }

        // Fenced code: ``` or ~~~
        static func fence(_ trimmed: String) -> String? {
            for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
                return marker
            }
            return nil
        }

        mutating func parseFencedCode(fence: String) {
            index += 1
            var code: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                code.append(lines[index])
                index += 1
            }
            index += 1 // closing fence
            blocks.append(.html("<pre><code>\(BKEpubPackageWriter.escape(code.joined(separator: "\n")))</code></pre>"))
        }

        mutating func parseIndentedCode() {
            var code: [String] = []
            while index < lines.count {
                let line = lines[index]
                if line.hasPrefix("    ") {
                    code.append(String(line.dropFirst(4)))
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty,
                          index + 1 < lines.count, lines[index + 1].hasPrefix("    ") {
                    code.append("")
                } else {
                    break
                }
                index += 1
            }
            blocks.append(.html("<pre><code>\(BKEpubPackageWriter.escape(code.joined(separator: "\n")))</code></pre>"))
        }

        static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes) else { return nil }
            let rest = trimmed.dropFirst(hashes)
            guard rest.isEmpty || rest.first == " " else { return nil }
            var text = rest.trimmingCharacters(in: .whitespaces)
            // Optional closing hashes.
            while text.hasSuffix("#") { text.removeLast() }
            return (hashes, text.trimmingCharacters(in: .whitespaces))
        }

        static func isRule(_ trimmed: String) -> Bool {
            let compact = trimmed.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
            return compact.allSatisfy { $0 == first }
        }

        mutating func parseQuote() {
            var inner: [String] = []
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { break }
                if trimmed.hasPrefix(">") {
                    var content = trimmed.dropFirst()
                    if content.first == " " { content = content.dropFirst() }
                    inner.append(String(content))
                } else {
                    inner.append(trimmed) // lazy continuation
                }
                index += 1
            }
            blocks.append(.html("<blockquote>\(BKMarkdown.html(from: inner.joined(separator: "\n")))</blockquote>"))
        }

        /// The list marker at the start of `line`: whether it's ordered, and how far the content is indented.
        static func listMarker(_ line: String) -> (ordered: Bool, contentIndent: Int, start: Int)? {
            let indent = line.prefix(while: { $0 == " " }).count
            guard indent < 4 else { return nil }
            let rest = line.dropFirst(indent)
            if let first = rest.first, "-*+".contains(first) {
                let after = rest.dropFirst()
                guard after.first == " " else { return nil }
                if isRule(String(rest)) { return nil }
                return (false, indent + 2, 1)
            }
            let digits = rest.prefix(while: { $0.isNumber })
            guard (1...9).contains(digits.count) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let delimiter = after.first, delimiter == "." || delimiter == ")",
                  after.dropFirst().first == " " else { return nil }
            return (true, indent + digits.count + 2, Int(digits) ?? 1)
        }

        mutating func parseList() {
            guard let first = Self.listMarker(lines[index]) else { return }
            var items: [String] = []
            var current: [String] = []
            var loose = false
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let marker = Self.listMarker(line), marker.ordered == first.ordered,
                   line.prefix(while: { $0 == " " }).count < first.contentIndent {
                    if !current.isEmpty { items.append(current.joined(separator: "\n")) }
                    current = [String(line.dropFirst(min(marker.contentIndent, line.count)))]
                } else if trimmed.isEmpty {
                    // A blank line ends the list unless the next line continues this item or starts another.
                    let next = index + 1 < lines.count ? lines[index + 1] : ""
                    let nextIndent = next.prefix(while: { $0 == " " }).count
                    let continues = !next.trimmingCharacters(in: .whitespaces).isEmpty
                        && (nextIndent >= first.contentIndent || Self.listMarker(next)?.ordered == first.ordered)
                    guard continues else { break }
                    loose = true
                    current.append("")
                } else if line.prefix(while: { $0 == " " }).count >= first.contentIndent {
                    current.append(String(line.dropFirst(first.contentIndent)))
                } else if Self.listMarker(line) != nil || Self.atxHeading(trimmed) != nil || trimmed.hasPrefix(">") {
                    break
                } else {
                    current.append(trimmed) // lazy continuation of the item's paragraph
                }
                index += 1
            }
            if !current.isEmpty { items.append(current.joined(separator: "\n")) }

            let tag = first.ordered ? "ol" : "ul"
            let start = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
            let rendered = items.map { item -> String in
                var html = BKMarkdown.html(from: item)
                // Tight lists show items without paragraph spacing.
                if !loose, html.hasPrefix("<p>"), let end = html.range(of: "</p>") {
                    html = String(html[html.index(html.startIndex, offsetBy: 3)..<end.lowerBound]) + html[end.upperBound...]
                }
                return "<li>\(html)</li>"
            }.joined()
            blocks.append(.html("<\(tag)\(start)>\(rendered)</\(tag)>"))
        }

        static func tableCells(_ line: String) -> [String] {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") { trimmed.removeFirst() }
            if trimmed.hasSuffix("|") { trimmed.removeLast() }
            return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        static func isTableStart(at index: Int, in lines: [String]) -> Bool {
            guard index + 1 < lines.count, lines[index].contains("|") else { return false }
            let separator = tableCells(lines[index + 1])
            return separator.count >= 1 && separator.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { "-:".contains($0) } && cell.contains("-")
            }
        }

        mutating func parseTable() {
            let header = Self.tableCells(lines[index])
            let alignments = Self.tableCells(lines[index + 1]).map { cell -> String in
                switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                case (true, true): " style=\"text-align: center\""
                case (false, true): " style=\"text-align: right\""
                default: ""
                }
            }
            index += 2
            func row(_ cells: [String], tag: String) -> String {
                "<tr>" + cells.enumerated().map { offset, cell in
                    let align = offset < alignments.count ? alignments[offset] : ""
                    return "<\(tag)\(align)>\(BKMarkdown.inline(cell))</\(tag)>"
                }.joined() + "</tr>"
            }
            var body = ""
            while index < lines.count, lines[index].contains("|"),
                  !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                body += row(Self.tableCells(lines[index]), tag: "td")
                index += 1
            }
            blocks.append(.html("<table><thead>\(row(header, tag: "th"))</thead><tbody>\(body)</tbody></table>"))
        }

        mutating func parseParagraph() {
            var text: [String] = []
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || Self.fence(trimmed) != nil || Self.atxHeading(trimmed) != nil
                    || trimmed.hasPrefix(">") || (Self.listMarker(line) != nil && !text.isEmpty && Self.listMarker(line)?.ordered == false) {
                    break
                }
                // Setext headings: a line of === or --- under the paragraph.
                if !text.isEmpty, !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) || trimmed.allSatisfy({ $0 == "-" }) {
                    let level = trimmed.first == "=" ? 1 : 2
                    let joined = text.joined(separator: " ")
                    blocks.append(.heading(level: level, html: BKMarkdown.inline(joined), plainText: BKMarkdown.plainText(joined)))
                    index += 1
                    return
                }
                if Self.isRule(trimmed), !text.isEmpty { break }
                // Two trailing spaces force a line break.
                text.append(line.hasSuffix("  ") ? trimmed + "\u{0}" : trimmed)
                index += 1
            }
            let html = BKMarkdown.inline(text.joined(separator: "\n"))
                .replacingOccurrences(of: "\u{0}\n", with: "<br/>\n")
                .replacingOccurrences(of: "\u{0}", with: "")
            blocks.append(.html("<p>\(html)</p>"))
        }
    }

    // MARK: - Inline

    /// Renders inline Markdown (emphasis, code, links, images…) as XHTML.
    static func inline(_ text: String) -> String {
        var protected: [String] = []
        func protect(_ html: String) -> String {
            protected.append(html)
            return "\u{1}\(protected.count - 1)\u{2}"
        }

        var source = text
        // Backslash escapes.
        source = replace(#"\\([\\`*_{}\[\]()#+\-.!|~<>])"#, in: source) { groups in
            protect(BKEpubPackageWriter.escape(groups[1]))
        }
        // Code spans first: nothing inside them is formatted.
        source = replace(#"(`+)(.+?)\1"#, in: source) { groups in
            protect("<code>\(BKEpubPackageWriter.escape(groups[2].trimmingCharacters(in: .whitespaces)))</code>")
        }
        // Images, then links.
        source = replace(#"!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"([^"]*)")?\s*\)"#, in: source) { groups in
            let title = groups[3].isEmpty ? "" : " title=\"\(BKEpubPackageWriter.escape(groups[3]))\""
            return protect("<img src=\"\(BKEpubPackageWriter.escape(groups[2]))\" alt=\"\(BKEpubPackageWriter.escape(groups[1]))\"\(title)/>")
        }
        source = replace(#"\[([^\]]+)\]\(\s*<?([^)\s>]+)>?(?:\s+"([^"]*)")?\s*\)"#, in: source) { groups in
            protect("<a href=\"\(BKEpubPackageWriter.escape(groups[2]))\">") + groups[1] + protect("</a>")
        }
        source = replace(#"<((?:https?|mailto):[^>\s]+)>"#, in: source) { groups in
            protect("<a href=\"\(BKEpubPackageWriter.escape(groups[1]))\">\(BKEpubPackageWriter.escape(groups[1]))</a>")
        }

        var html = BKEpubPackageWriter.escape(source)
        html = replace(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: html) { "<strong>\($0[2])</strong>" }
        html = replace(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?!\*)"#, in: html) { "<em>\($0[1])</em>" }
        html = replace(#"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"#, in: html) { "<em>\($0[1])</em>" }
        html = replace(#"~~(?=\S)(.+?)(?<=\S)~~"#, in: html) { "<del>\($0[1])</del>" }

        // Restore protected pieces (they may nest, e.g. code inside a link).
        while let range = html.range(of: "\u{1}(\\d+)\u{2}", options: .regularExpression) {
            let number = Int(html[range].dropFirst().dropLast()) ?? 0
            html.replaceSubrange(range, with: protected[number])
        }
        return html
    }

    /// Heading text without Markdown markup, for the table of contents.
    static func plainText(_ text: String) -> String {
        let html = inline(text)
        let stripped = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Replaces each match of `pattern`; `transform` gets the match and its capture groups ("" when absent).
    private static func replace(_ pattern: String, in string: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return string }
        let nsString = string as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: nsString.length)) {
            result += nsString.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { group -> String in
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : nsString.substring(with: range)
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        result += nsString.substring(from: last)
        return result
    }
}
