//
//  BKTextBookConverter.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import NaturalLanguage
import BookKitCore

/// Turns plain text and Markdown files into books for the EPUB reader: chapters are split at
/// headings ("Chapter 1" lines in plain text), and very long chapters are cut into parts so pages
/// stay quick to lay out.
public enum BKTextBookConverter {

    /// Characters per chapter part before a long chapter is split (at a paragraph boundary).
    static let partLength = 60_000

    /// Bump when the generated chapter layout changes. Highlights point at chapters, so a file
    /// converted differently becomes a new book rather than one with misplaced highlights.
    static let layoutVersion = 1

    /// Converts `fileURL` (`.txt` or `.md`) into an unzipped EPUB at `destination` and parses it.
    /// The book's identifier comes from the file's contents, so re-importing it keeps highlights.
    public static func convert(_ fileURL: URL, to destination: URL) throws -> BKEpubBook {
        guard let format = BKBookFormat(fileURL: fileURL), format == .plainText || format == .markdown else {
            throw BKBookError.unsupportedFormat(fileURL.pathExtension)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw BKBookError.unreadable(error.localizedDescription)
        }
        guard let text = decode(data) else { throw BKBookError.unreadable("Unknown text encoding") }

        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        var writer = format == .markdown
            ? markdownBook(text, fallbackTitle: fallbackTitle)
            : plainTextBook(text, fallbackTitle: fallbackTitle)
        writer.identifier = BKEpubPackageWriter.identifier(for: data + Data("bookkit-text-\(layoutVersion)".utf8))
        writer.language = language(of: text)
        writer.resources = format == .markdown
            ? localImages(in: &writer.chapters, relativeTo: fileURL.deletingLastPathComponent())
            : []
        try writer.write(to: destination)
        return try BKEpubParser.parse(from: destination)
    }

    // MARK: - Markdown

    static func markdownBook(_ text: String, fallbackTitle: String) -> BKEpubPackageWriter {
        let blocks = BKMarkdown.blocks(from: stripFrontMatter(text).body)
        let frontMatter = stripFrontMatter(text).fields

        let headingLevels = blocks.compactMap { block -> Int? in
            if case let .heading(level, _, _) = block { return level }
            return nil
        }
        // A single top-level heading names the book (it stays in the text, opening the first chapter).
        var title = frontMatter["title"] ?? fallbackTitle
        if frontMatter["title"] == nil, headingLevels.filter({ $0 == 1 }).count == 1,
           case let .heading(1, _, plain)? = blocks.first(where: { if case .heading = $0 { return true }; return false }) {
            title = plain
        }
        let remainingLevels = blocks.compactMap { block -> Int? in
            if case let .heading(level, _, _) = block { return level }
            return nil
        }
        // Chapters start at the highest heading level that appears more than once.
        let splitLevel = (1...6).first { level in remainingLevels.filter { $0 == level }.count >= 2 }
            ?? remainingLevels.min()

        var chapters: [BKEpubPackageWriter.Chapter] = []
        var current = BKEpubPackageWriter.Chapter(title: nil, body: "")
        var sectionCount = 0
        func flush() {
            if !current.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || current.title != nil {
                chapters.append(current)
            }
        }
        for block in blocks {
            switch block {
            case let .heading(level, html, plain):
                if let splitLevel, level <= splitLevel {
                    flush()
                    current = BKEpubPackageWriter.Chapter(title: plain, body: "<h\(level)>\(html)</h\(level)>\n")
                } else if let splitLevel, level == splitLevel + 1 {
                    sectionCount += 1
                    let id = "section-\(sectionCount)"
                    current.sections.append((plain, id))
                    current.body += "<h\(level) id=\"\(id)\">\(html)</h\(level)>\n"
                } else {
                    current.body += "<h\(level)>\(html)</h\(level)>\n"
                }
            case let .html(html):
                current.body += html + "\n"
            }
        }
        flush()
        // Untitled text before the first chapter heading opens the book.
        if let first = chapters.first, first.title == nil {
            chapters[0].title = title
        }
        if chapters.isEmpty {
            chapters = [BKEpubPackageWriter.Chapter(title: title, body: "")]
        }

        let authors = frontMatter["author"].map { [$0] } ?? []
        return BKEpubPackageWriter(title: title, authors: authors, identifier: "",
                                   chapters: splitLongChapters(chapters))
    }

    /// YAML front matter (`---` … `---`) at the top: simple `key: value` fields, and the remaining text.
    static func stripFrontMatter(_ text: String) -> (fields: [String: String], body: String) {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([:], text)
        }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { fields[key] = value }
        }
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }

    // MARK: - Plain text

    static func plainTextBook(_ text: String, fallbackTitle: String) -> BKEpubPackageWriter {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        // Project Gutenberg style header fields.
        var title = fallbackTitle
        var authors: [String] = []
        var headerLines: Set<Int> = []
        for (index, line) in lines.prefix(80).enumerated() {
            if line.hasPrefix("Title:") {
                title = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                headerLines.insert(index)
            } else if line.hasPrefix("Author:"), authors.isEmpty {
                authors = [line.dropFirst(7).trimmingCharacters(in: .whitespaces)]
                headerLines.insert(index)
            }
        }

        // Paragraphs are separated by blank lines; files with (almost) none use one line per paragraph.
        let blankLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let linePerParagraph = blankLines * 10 < lines.count
        var paragraphs: [String] = []
        var buffer: [String] = []
        for (index, line) in lines.enumerated() where !headerLines.contains(index) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !buffer.isEmpty { paragraphs.append(buffer.joined(separator: " ")); buffer = [] }
            } else if linePerParagraph || isChapterHeading(trimmed) {
                if !buffer.isEmpty { paragraphs.append(buffer.joined(separator: " ")); buffer = [] }
                paragraphs.append(trimmed)
            } else {
                buffer.append(trimmed)
            }
        }
        if !buffer.isEmpty { paragraphs.append(buffer.joined(separator: " ")) }

        var chapters: [BKEpubPackageWriter.Chapter] = []
        var current = BKEpubPackageWriter.Chapter(title: nil, body: "")
        for paragraph in paragraphs {
            if isChapterHeading(paragraph) {
                if !current.body.isEmpty { chapters.append(current) }
                current = BKEpubPackageWriter.Chapter(title: paragraph,
                                                      body: "<h2>\(BKEpubPackageWriter.escape(paragraph))</h2>\n")
            } else {
                current.body += "<p>\(BKEpubPackageWriter.escape(paragraph))</p>\n"
            }
        }
        if !current.body.isEmpty { chapters.append(current) }
        if let first = chapters.first, first.title == nil { chapters[0].title = title }
        if chapters.isEmpty { chapters = [BKEpubPackageWriter.Chapter(title: title, body: "")] }

        return BKEpubPackageWriter(title: title, authors: authors, identifier: "",
                                   chapters: splitLongChapters(chapters))
    }

    /// Short lines like "Chapter 1", "CHAPTER IV. The Storm", "Part Two", "Prologue".
    static func isChapterHeading(_ line: String) -> Bool {
        guard line.count <= 80 else { return false }
        let number = #"([0-9]+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|last)"#
        let pattern = #"^(chapter|part|book|section)\s+"# + number + #"\b[.:\-–—]?(\s.{0,60})?$|^(prologue|epilogue|preface|introduction|foreword|afterword)\b.{0,40}$"#
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Shared

    /// Cuts chapters longer than `partLength` at paragraph boundaries; later parts have no TOC entry.
    static func splitLongChapters(_ chapters: [BKEpubPackageWriter.Chapter]) -> [BKEpubPackageWriter.Chapter] {
        chapters.flatMap { chapter -> [BKEpubPackageWriter.Chapter] in
            guard chapter.body.count > partLength else { return [chapter] }
            var parts: [BKEpubPackageWriter.Chapter] = []
            var part = ""
            // Top-level blocks are one per line in the generated body.
            for line in chapter.body.components(separatedBy: "\n") {
                if part.count + line.count > partLength, !part.isEmpty {
                    parts.append(BKEpubPackageWriter.Chapter(title: parts.isEmpty ? chapter.title : nil, body: part))
                    part = ""
                }
                part += line + "\n"
            }
            if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(BKEpubPackageWriter.Chapter(title: parts.isEmpty ? chapter.title : nil, body: part))
            }
            // Section anchors stay with whichever part holds them.
            for section in chapter.sections {
                guard let index = parts.firstIndex(where: { $0.body.contains("id=\"\(section.id)\"") }) else { continue }
                if parts[index].title != nil {
                    parts[index].sections.append(section)
                } else {
                    // The first section in an untitled part names the part in the table of contents.
                    parts[index].title = section.title
                }
            }
            return parts
        }
    }

    /// Copies images referenced by relative paths into the package and points the markup at them.
    static func localImages(in chapters: inout [BKEpubPackageWriter.Chapter], relativeTo directory: URL) -> [BKEpubPackageWriter.Resource] {
        var resources: [BKEpubPackageWriter.Resource] = []
        var hrefs: [String: String] = [:]
        let pattern = try? NSRegularExpression(pattern: #"<img src="([^"]+)""#)
        for index in chapters.indices {
            let body = chapters[index].body as NSString
            var updated = chapters[index].body
            for match in pattern?.matches(in: body as String, range: NSRange(location: 0, length: body.length)) ?? [] {
                let src = body.substring(with: match.range(at: 1))
                let decoded = src.replacingOccurrences(of: "&amp;", with: "&")
                guard !decoded.contains("://"), !decoded.hasPrefix("data:") else { continue }
                let source = directory.appendingPathComponent(decoded.removingPercentEncoding ?? decoded).standardizedFileURL
                // Only files next to (or below) the document are copied.
                guard source.path.hasPrefix(directory.standardizedFileURL.path) else { continue }
                if hrefs[src] == nil, let data = try? Data(contentsOf: source) {
                    let href = "images/\(resources.count + 1)-\(source.lastPathComponent)"
                    resources.append(.init(href: href, data: data))
                    hrefs[src] = href
                }
                if let href = hrefs[src] {
                    updated = updated.replacingOccurrences(of: "<img src=\"\(src)\"", with: "<img src=\"../\(BKEpubPackageWriter.escape(href))\"")
                }
            }
            chapters[index].body = updated
        }
        return resources
    }

    /// Decodes text as UTF-8 (with or without BOM), UTF-16 with BOM, or Windows-1252 as a last resort.
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.hasPrefix("\u{FEFF}") ? String(utf8.dropFirst()) : utf8
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    /// The text's dominant language as a BCP 47 code, or "und".
    static func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4000)))
        return recognizer.dominantLanguage?.rawValue ?? "und"
    }
}
