//
//  BKTextBookConverterTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import Testing
import BookKitCore
@testable import BookKitParser

@Suite("Markdown")
struct BKMarkdownTests {

    @Test func inlineFormatting() {
        #expect(BKMarkdown.inline("**bold** and *em* and _em_ and ~~gone~~")
                == "<strong>bold</strong> and <em>em</em> and <em>em</em> and <del>gone</del>")
        #expect(BKMarkdown.inline("`a*b*c` <b>raw</b>") == "<code>a*b*c</code> &lt;b&gt;raw&lt;/b&gt;")
        #expect(BKMarkdown.inline("[**Swift**](https://swift.org)") == "<a href=\"https://swift.org\"><strong>Swift</strong></a>")
        #expect(BKMarkdown.inline("![A cat](cat.png \"Cat\")") == "<img src=\"cat.png\" alt=\"A cat\" title=\"Cat\"/>")
        #expect(BKMarkdown.inline(#"snake_case_name and 2*3*4 and \*not em\*"#) == "snake_case_name and 2*3*4 and *not em*")
    }

    @Test func blocks() {
        let markdown = """
        # Title

        Para one
        continues here.

        > Quoted *text*

        - one
        - two
          - nested

        1. first
        2. second

        ```
        let x = 1 < 2
        ```

        | Name | Age |
        | :--- | --: |
        | Ann  | 30  |

        ---
        """
        let html = BKMarkdown.html(from: markdown)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<p>Para one\ncontinues here.</p>"))
        #expect(html.contains("<blockquote><p>Quoted <em>text</em></p></blockquote>"))
        #expect(html.contains("<ul><li>one</li><li>two\n<ul><li>nested</li></ul></li></ul>"))
        #expect(html.contains("<ol><li>first</li><li>second</li></ol>"))
        #expect(html.contains("<pre><code>let x = 1 &lt; 2</code></pre>"))
        #expect(html.contains("<th>Name</th><th style=\"text-align: right\">Age</th>"))
        #expect(html.contains("<td>Ann</td>"))
        #expect(html.hasSuffix("<hr/>"))
    }

    @Test func setextHeadings() {
        let blocks = BKMarkdown.blocks(from: "Big\n===\n\nSmall\n---\n")
        #expect(blocks == [.heading(level: 1, html: "Big", plainText: "Big"),
                           .heading(level: 2, html: "Small", plainText: "Small")])
    }
}

@Suite("Text book conversion")
struct BKTextBookConverterTests {

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    private func file(_ name: String, _ contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Every generated document must be well-formed XML (the nav is read with `XMLParser`).
    private func expectWellFormed(_ book: BKEpubBook) {
        for index in book.spine.indices {
            guard let url = book.chapterURL(forSpineIndex: index) else {
                Issue.record("No URL for spine \(index)")
                continue
            }
            let parser = XMLParser(contentsOf: url)
            #expect(parser?.parse() == true, "\(url.lastPathComponent): \(String(describing: parser?.parserError))")
        }
    }

    @Test func markdownSplitsChaptersAtHeadings() throws {
        let url = try file("notes.md", """
        # My Book

        Intro text.

        ## One

        Text of one.

        ### Detail

        More.

        ## Two

        Text of two.
        """)
        let book = try BKTextBookConverter.convert(url, to: directory.appendingPathComponent("out"))
        #expect(book.metadata.title == "My Book")
        #expect(book.spine.count == 3)
        #expect(book.toc.map(\.label) == ["My Book", "One", "Two"])
        #expect(book.toc[1].children.map(\.label) == ["Detail"])
        #expect(book.toc[1].children.first?.href?.hasSuffix("#section-1") == true)
        // The title heading still opens the book.
        let opening = try String(contentsOf: try #require(book.chapterURL(forSpineIndex: 0)), encoding: .utf8)
        #expect(opening.contains("<h1>My Book</h1>"))
        expectWellFormed(book)
    }

    @Test func markdownFrontMatterAndImages() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: directory.appendingPathComponent("pic.png"))
        let url = try file("doc.markdown", """
        ---
        title: "Front Title"
        author: Jane Doe
        ---
        Hello ![pic](pic.png) and ![remote](https://example.com/a.png)
        """)
        let book = try BKTextBookConverter.convert(url, to: directory.appendingPathComponent("out"))
        #expect(book.metadata.title == "Front Title")
        #expect(book.metadata.creators == ["Jane Doe"])
        #expect(book.manifest.contains { $0.href == "images/1-pic.png" && $0.mediaType == "image/png" })
        let chapter = try String(contentsOf: try #require(book.chapterURL(forSpineIndex: 0)), encoding: .utf8)
        #expect(chapter.contains("src=\"../images/1-pic.png\""))
        #expect(chapter.contains("src=\"https://example.com/a.png\""))
        expectWellFormed(book)
    }

    @Test func plainTextFindsChaptersAndHeader() throws {
        let url = try file("novel.txt", """
        Title: The Long Road
        Author: A. Writer

        Part of the reason I left was the weather.

        CHAPTER I. The Start

        It began & ended <quietly>.

        Chapter 2

        The second chapter.
        """)
        let book = try BKTextBookConverter.convert(url, to: directory.appendingPathComponent("out"))
        #expect(book.metadata.title == "The Long Road")
        #expect(book.metadata.creators == ["A. Writer"])
        #expect(book.toc.map(\.label) == ["The Long Road", "CHAPTER I. The Start", "Chapter 2"])
        let chapter = try String(contentsOf: try #require(book.chapterURL(forSpineIndex: 1)), encoding: .utf8)
        #expect(chapter.contains("<p>It began &amp; ended &lt;quietly&gt;.</p>"))
        // The header lines name the book; they aren't part of its text.
        let opening = try String(contentsOf: try #require(book.chapterURL(forSpineIndex: 0)), encoding: .utf8)
        #expect(!opening.contains("Title:") && !opening.contains("Author:"))
        #expect(opening.contains("<p>Part of the reason I left was the weather.</p>"))
        expectWellFormed(book)
    }

    @Test func oneLinePerParagraphText() {
        let writer = BKTextBookConverter.plainTextBook("First line.\nSecond line.\nThird line.", fallbackTitle: "x")
        #expect(writer.chapters.first?.body == "<p>First line.</p>\n<p>Second line.</p>\n<p>Third line.</p>\n")
    }

    @Test func longChaptersAreSplitIntoParts() {
        let paragraph = String(repeating: "word ", count: 2000)
        let text = (0..<20).map { _ in paragraph }.joined(separator: "\n\n")
        let writer = BKTextBookConverter.plainTextBook(text, fallbackTitle: "Big")
        #expect(writer.chapters.count > 1)
        #expect(writer.chapters.first?.title == "Big")
        #expect(writer.chapters.dropFirst().allSatisfy { $0.title == nil })
        #expect(writer.chapters.allSatisfy { $0.body.count <= BKTextBookConverter.partLength + paragraph.count + 20 })
    }

    @Test func sameFileKeepsItsIdentifier() throws {
        let url = try file("same.txt", "Some text.")
        let first = try BKTextBookConverter.convert(url, to: directory.appendingPathComponent("a"))
        let second = try BKTextBookConverter.convert(url, to: directory.appendingPathComponent("b"))
        #expect(first.uniqueIdentifier == second.uniqueIdentifier)
        let other = try BKTextBookConverter.convert(try file("other.txt", "Other text."), to: directory.appendingPathComponent("c"))
        #expect(other.uniqueIdentifier != first.uniqueIdentifier)
    }

    @Test func decodesLegacyEncodings() {
        #expect(BKTextBookConverter.decode(Data([0xEF, 0xBB, 0xBF, 0x68, 0x69])) == "hi")
        #expect(BKTextBookConverter.decode(Data([0x63, 0x61, 0x66, 0xE9])) == "café") // Windows-1252
        #expect(BKTextBookConverter.decode(Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])) == "hi")
    }

    @Test func rejectsOtherFormats() throws {
        let url = try file("book.pdf", "%PDF")
        #expect(throws: BKBookError.unsupportedFormat("pdf")) {
            try BKTextBookConverter.convert(url, to: directory.appendingPathComponent("out"))
        }
        #expect(BKBookFormat(fileURL: URL(fileURLWithPath: "/a/B.MD")) == .markdown)
        #expect(BKBookFormat(fileURL: URL(fileURLWithPath: "/a/b.txt")) == .plainText)
    }
}
