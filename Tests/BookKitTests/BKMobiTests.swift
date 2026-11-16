//
//  BKMobiTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import Testing
import BookKitCore
@testable import BookKitParser

@Suite("MOBI")
struct BKMobiTests {

    @Test func palmDOCDecompression() {
        // Literals, a back reference (distance 3, length 3), a space pair and a literal run.
        let compressed = Data([0x61, 0x62, 0x63, 0x80, 0x18, 0xC1, 0x02, 0x78, 0x79])
        #expect(String(decoding: BKMobiFile.palmDOCDecompress(compressed), as: UTF8.self) == "abcabc Axy")
        // An overlapping reference (distance 1, length 7) repeats the last byte.
        #expect(String(decoding: BKMobiFile.palmDOCDecompress(Data([0x7A, 0x80, 0x0C])), as: UTF8.self) == "zzzzzzzz")
    }

    @Test func trailingEntries() {
        let indexed = Data("hello".utf8) + Data("XY".utf8) + Data([0x83])
        #expect(BKMobiFile.trailingEntriesSize(indexed, flags: 0b10) == 3)
        let both = Data("hello".utf8) + Data([0x00]) + Data("XY".utf8) + Data([0x83])
        #expect(BKMobiFile.trailingEntriesSize(both, flags: 0b11) == 4)
        #expect(BKMobiFile.trailingEntriesSize(Data("hello".utf8), flags: 0) == 0)
    }

    @Test func variableWidthValues() {
        #expect(BKMobiFile.variableWidthValue([0x81], at: 0) == (1, 1))
        #expect(BKMobiFile.variableWidthValue([0x01, 0x80], at: 0) == (2, 128))
    }

    @Test func convertsAMobi6Book() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Tiny.mobi")
        try Self.makeMobi6().write(to: url)

        let book = try BKMobiConverter.convert(url, to: directory.appendingPathComponent("out"))
        #expect(book.metadata.title == "Updated Title")
        #expect(book.metadata.creators == ["Ann Author"])
        #expect(book.metadata.language == "en")
        #expect(book.spine.count == 2)
        #expect(book.manifest.contains { $0.href == "images/resource00001.png" })

        let first = try String(contentsOf: try #require(book.chapterURL(forSpineIndex: 0)), encoding: .utf8)
        let second = try String(contentsOf: try #require(book.chapterURL(forSpineIndex: 1)), encoding: .utf8)
        #expect(first.contains("<h1>One</h1>"))
        #expect(first.contains("café")) // UTF-8 text
        #expect(first.contains("src=\"../images/resource00001.png\""))
        #expect(first.range(of: #"href="chapter0002\.xhtml#filepos\d+""#, options: .regularExpression) != nil)
        #expect(!first.contains("mbp:") && !first.contains("filepos=") && !first.contains("<guide"))
        // The link's anchor opens the second chapter, not the end of the first.
        #expect(second.range(of: #"<a id="filepos\d+"></a><h1>Two</h1>"#, options: .regularExpression) != nil)
        #expect(book.toc.map(\.label) == ["One", "Two"])
    }

    @Test func rejectsOtherFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mobi")
        try Data(repeating: 0, count: 200).write(to: url)
        #expect(throws: BKBookError.self) {
            try BKMobiConverter.convert(url, to: url.deletingLastPathComponent().appendingPathComponent("out"))
        }
        #expect(BKBookFormat(fileURL: URL(fileURLWithPath: "/b/Book.AZW3")) == .mobi)
    }

    // MARK: - A minimal MOBI 6 file

    private static func be32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) } }
    private static func be16(_ value: Int) -> Data { withUnsafeBytes(of: UInt16(value).bigEndian) { Data($0) } }

    static func makeMobi6() -> Data {
        // Text: two pages, a filepos link to the second, an image.
        func html(target: Int) -> String {
            "<html><head><guide></guide></head><body><h1>One</h1><p>A café. Go to <a filepos=\(String(format: "%010d", target))>two</a></p>"
                + "<p><img recindex=\"00001\"/></p><mbp:pagebreak/><h1>Two</h1><p>Second.</p></body></html>"
        }
        let probe = Data(html(target: 0).utf8)
        let target = probe.range(of: Data("<h1>Two".utf8))!.lowerBound
        let text = Data(html(target: target).utf8)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // Record 0: PalmDOC header, MOBI header (0x108 bytes), EXTH, full name.
        let headerLength = 0x108
        var mobi = Data(count: headerLength)
        func put(_ offset: Int, _ value: Data) { mobi.replaceSubrange((offset - 16)..<(offset - 16 + value.count), with: value) }
        put(16, Data("MOBI".utf8)); put(20, be32(headerLength)); put(24, be32(2)); put(28, be32(65001)); put(36, be32(6))
        put(0x50, be32(2)); put(0x6C, be32(2)); put(0x80, be32(0x40))
        for offset in [0xC0, 0xF4, 0xF8, 0xFC] { put(offset, be32(0xFFFF_FFFF)) }
        var exth = Data()
        for (type, value) in [(100, "Ann Author"), (503, "Updated Title"), (524, "en")] {
            exth += be32(type) + be32(8 + value.utf8.count) + Data(value.utf8)
        }
        exth = Data("EXTH".utf8) + be32(12 + exth.count) + be32(3) + exth
        let name = Data("Tiny Book".utf8)
        var record0 = be16(1) + be16(0) + be32(text.count) + be16(1) + be16(4096) + be16(0) + be16(0)
        let nameOffset = 16 + headerLength + exth.count
        put(0x54, be32(nameOffset)); put(0x58, be32(name.count))
        record0 += mobi + exth + name + Data(count: 4)

        // Palm database: header, record list, records.
        let records = [record0, text, png]
        var file = Data("Tiny".utf8) + Data(count: 28) + Data(count: 28) + Data("BOOKMOBI".utf8) + Data(count: 8) + be16(records.count)
        var offset = 78 + records.count * 8 + 2
        for (index, record) in records.enumerated() {
            file += be32(offset) + be32(index * 2)
            offset += record.count
        }
        file += Data(count: 2)
        for record in records { file += record }
        return file
    }
}
