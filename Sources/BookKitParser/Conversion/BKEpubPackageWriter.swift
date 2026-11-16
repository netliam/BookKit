//
//  BKEpubPackageWriter.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import CryptoKit

/// Writes converted books (plain text, Markdown, MOBI…) as an unzipped EPUB 3 folder, so they open in
/// the same reader as EPUBs, with its themes, search, highlights and page numbers.
struct BKEpubPackageWriter {

    struct Chapter {
        /// Title for the table of contents; `nil` for continuation parts of a long chapter.
        var title: String?
        /// XHTML for inside `<body>`.
        var body: String
        /// Sub-entries for the table of contents: (title, element id inside this chapter).
        var sections: [(title: String, id: String)] = []
    }

    struct Resource {
        /// Path inside the package, relative to the OPF (e.g. `images/cover.png`).
        let href: String
        let data: Data
    }

    var title: String
    var authors: [String] = []
    var language: String = "und"
    /// Stable identifier, so highlights and positions survive a re-import of the same file.
    var identifier: String
    var chapters: [Chapter]
    var resources: [Resource] = []
    /// Extra CSS for the converted markup (code blocks, tables…). The reader's own styles still apply.
    var stylesheet: String = BKEpubPackageWriter.defaultStylesheet

    /// A UUID derived from the file's bytes: the same file always gets the same identifier.
    static func identifier(for data: Data) -> String {
        let bytes = Array(SHA256.hash(data: data).prefix(16))
        var uuid = bytes
        uuid[6] = (uuid[6] & 0x0F) | 0x50 // version 5 style
        uuid[8] = (uuid[8] & 0x3F) | 0x80 // RFC 4122 variant
        let hex = uuid.map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return "urn:uuid:" + parts.joined(separator: "-")
    }

    /// Writes the package to `root` (replacing anything there) and returns it.
    @discardableResult
    func write(to root: URL) throws -> URL {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: root)
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: oebps.appendingPathComponent("text"), withIntermediateDirectories: true)

        try write("application/epub+zip", to: root.appendingPathComponent("mimetype"))
        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """, to: root.appendingPathComponent("META-INF/container.xml"))

        try write(stylesheet, to: oebps.appendingPathComponent("style.css"))
        for (index, chapter) in chapters.enumerated() {
            try write(chapterDocument(chapter), to: oebps.appendingPathComponent(chapterHref(index)))
        }
        for resource in resources {
            let url = oebps.appendingPathComponent(resource.href)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try resource.data.write(to: url)
        }
        try write(navDocument(), to: oebps.appendingPathComponent("nav.xhtml"))
        try write(packageDocument(), to: oebps.appendingPathComponent("content.opf"))
        return root
    }

    // MARK: - Documents

    private func chapterHref(_ index: Int) -> String {
        String(format: "text/chapter%04d.xhtml", index + 1)
    }

    private func chapterDocument(_ chapter: Chapter) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(Self.escape(language))" lang="\(Self.escape(language))">
        <head>
        <meta charset="utf-8"/>
        <title>\(Self.escape(chapter.title ?? title))</title>
        <link rel="stylesheet" type="text/css" href="../style.css"/>
        </head>
        <body>
        \(chapter.body)
        </body>
        </html>
        """
    }

    private func navDocument() -> String {
        var items = ""
        for (index, chapter) in chapters.enumerated() {
            guard let chapterTitle = chapter.title else { continue }
            let href = chapterHref(index)
            items += "<li><a href=\"\(href)\">\(Self.escape(chapterTitle))</a>"
            if !chapter.sections.isEmpty {
                items += "<ol>"
                for section in chapter.sections {
                    items += "<li><a href=\"\(href)#\(Self.escape(section.id))\">\(Self.escape(section.title))</a></li>"
                }
                items += "</ol>"
            }
            items += "</li>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><meta charset="utf-8"/><title>\(Self.escape(title))</title></head>
        <body>
        <nav epub:type="toc" id="toc"><ol>
        \(items)</ol></nav>
        </body>
        </html>
        """
    }

    private func packageDocument() -> String {
        var manifest = """
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="style" href="style.css" media-type="text/css"/>

        """
        var spine = ""
        for index in chapters.indices {
            manifest += "    <item id=\"chapter\(index + 1)\" href=\"\(chapterHref(index))\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "    <itemref idref=\"chapter\(index + 1)\"/>\n"
        }
        for (index, resource) in resources.enumerated() {
            manifest += "    <item id=\"res\(index + 1)\" href=\"\(Self.escape(resource.href))\" media-type=\"\(Self.mediaType(for: resource.href))\"/>\n"
        }
        let creators = authors.map { "    <dc:creator>\(Self.escape($0))</dc:creator>\n" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="3.0" unique-identifier="book-id" xmlns="http://www.idpf.org/2007/opf">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">\(Self.escape(identifier))</dc:identifier>
            <dc:title>\(Self.escape(title))</dc:title>
        \(creators)    <dc:language>\(Self.escape(language))</dc:language>
          </metadata>
          <manifest>
        \(manifest)  </manifest>
          <spine>
        \(spine)  </spine>
        </package>
        """
    }

    // MARK: - Helpers

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }

    /// Escapes text for XHTML content and attribute values.
    static func escape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    static func mediaType(for href: String) -> String {
        switch (href as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "css": "text/css"
        default: "application/octet-stream"
        }
    }

    static let defaultStylesheet = """
    body { font-family: ui-serif, Georgia, serif; }
    pre { white-space: pre-wrap; word-wrap: break-word; text-align: left; text-indent: 0; padding: 0.6em 0.8em; border-radius: 6px; background: rgba(128, 128, 128, 0.14); }
    pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 0.85em; }
    pre code { font-size: 1em; }
    blockquote { margin: 1em 0 1em 0.5em; padding-left: 0.8em; border-left: 3px solid rgba(128, 128, 128, 0.5); }
    blockquote p, li p, td, th { text-indent: 0; }
    table { border-collapse: collapse; margin: 1em 0; }
    th, td { border: 1px solid rgba(128, 128, 128, 0.5); padding: 0.25em 0.5em; text-align: left; }
    img { max-width: 100%; }
    hr { margin: 1.5em 0; }
    """
}
