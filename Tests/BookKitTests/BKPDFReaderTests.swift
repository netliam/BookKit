//
//  BKPDFReaderTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import PDFKit
import Testing
import UIKit
import BookKitCore
@testable import BookKitRendering

@Suite("PDF location")
struct BKPDFLocationTests {

    @Test func roundTrips() {
        let location = BKPDFLocation(pageIndex: 3, rects: [CGRect(x: 10, y: 20.5, width: 100, height: 12),
                                                           CGRect(x: 10, y: 5.25, width: 40, height: 12)])
        #expect(location.coords == "pdf|3|10.00,20.50,100.00,12.00;10.00,5.25,40.00,12.00")
        #expect(BKPDFLocation(coords: location.coords) == location)
        #expect(location.bounds == CGRect(x: 10, y: 5.25, width: 100, height: 27.25))
        #expect(BKPDFLocation(coords: "pdf|0|") == BKPDFLocation(pageIndex: 0))
    }

    @Test func rejectsOtherCoords() {
        #expect(BKPDFLocation(coords: "0000001>0000002>0000004") == nil)
        #expect(BKPDFLocation(coords: "pdf|x|") == nil)
        #expect(BKPDFLocation(coords: "pdf|1|1,2,3") == nil)
    }
}

@MainActor
@Suite("PDF reader")
struct BKPDFReaderTests {

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    /// A three-page PDF; page N says "Page N" and mentions "lighthouse" once.
    private func makePDF() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
        try renderer.writePDF(to: url) { context in
            for page in 1...3 {
                context.beginPage()
                let text = "Page \(page). The lighthouse keeper wrote in the log."
                (text as NSString).draw(in: CGRect(x: 20, y: 40, width: 260, height: 300),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        return url
    }

    private func makeReader(_ url: URL, store: BKJSONReaderStore) throws -> BKPDFReaderViewModel {
        let document = try #require(PDFDocument(url: url))
        return BKPDFReaderViewModel(document: document, fileURL: url,
                                    bookId: BKPDFReaderViewBuilder.identifier(forPDFAt: url),
                                    highlightStore: store, positionStore: store,
                                    menuConfiguration: BKHighlightMenuConfiguration())
    }

    @Test func highlightsAreSavedAndRedrawn() async throws {
        let url = try makePDF()
        let store = BKJSONReaderStore(directory: directory.appendingPathComponent("store"))
        let reader = try makeReader(url, store: store)
        await reader.load()

        let match = try #require(reader.document.findString("lighthouse", withOptions: .caseInsensitive).dropFirst().first)
        reader.highlight(match, style: .highlight, color: "#C0ED72")
        let saved = try #require(reader.marks.first)
        #expect(saved.text == "lighthouse")
        #expect(saved.spineIndex == 1)
        #expect(saved.color == "#C0ED72")
        let location = try #require(BKPDFLocation(coords: saved.coords))
        #expect(location.pageIndex == 1)
        #expect(!location.rects.isEmpty)
        #expect(reader.document.page(at: 1)?.annotations.contains { $0.type == "Highlight" } == true)

        // Tapping inside the highlight finds it.
        let page = try #require(reader.document.page(at: 1))
        let center = CGPoint(x: location.bounds.midX, y: location.bounds.midY)
        #expect(reader.highlight(at: center, on: page)?.uuid == saved.uuid)

        // A fresh reader draws it again from the store.
        try await Task.sleep(nanoseconds: 100_000_000)
        let reopened = try makeReader(url, store: store)
        await reopened.load()
        #expect(reopened.marks.map(\.uuid) == [saved.uuid])
        #expect(reopened.document.page(at: 1)?.annotations.contains { $0.type == "Highlight" } == true)

        reopened.recolor(saved, style: .underline, color: "#F02814")
        #expect(reopened.document.page(at: 1)?.annotations.contains { $0.type == "Underline" } == true)
        reopened.delete(try #require(reopened.marks.first))
        #expect(reopened.document.page(at: 1)?.annotations.isEmpty == true)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await store.highlights(bookId: reopened.bookId).isEmpty)
    }

    @Test func bookmarksAndPosition() async throws {
        let url = try makePDF()
        let store = BKJSONReaderStore(directory: directory.appendingPathComponent("store"))
        let reader = try makeReader(url, store: store)
        await reader.load()

        reader.pageDidChange(to: 2)
        #expect(!reader.isCurrentPageBookmarked)
        reader.toggleBookmark()
        #expect(reader.isCurrentPageBookmarked)
        #expect(reader.marks.first?.text.hasPrefix("Page 3.") == true)
        reader.toggleBookmark()
        #expect(!reader.isCurrentPageBookmarked)

        // The position is saved once the page settles.
        var position = await store.position(bookId: reader.bookId)
        let deadline = Date().addingTimeInterval(5)
        while position == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            position = await store.position(bookId: reader.bookId)
        }
        #expect(position.flatMap { BKPDFLocation(coords: $0.coords) }?.pageIndex == 2)
    }

    @Test func searchFindsEveryPage() async throws {
        let reader = try makeReader(try makePDF(), store: BKJSONReaderStore(directory: directory.appendingPathComponent("store")))
        reader.search("Lighthouse")
        let deadline = Date().addingTimeInterval(10)
        while reader.isSearching, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(reader.searchResults.map(\.pageIndex) == [0, 1, 2])
        #expect(reader.searchResults.first?.snippet.contains("lighthouse keeper") == true)
        reader.search("")
        #expect(reader.searchResults.isEmpty && !reader.isSearching)
    }

    @Test func retypingCancelsTheOldSearch() async throws {
        let reader = try makeReader(try makePDF(), store: BKJSONReaderStore(directory: directory.appendingPathComponent("store")))
        // Each keystroke restarts the search; the cancelled ones mustn't end or add to the new one.
        reader.search("l")
        reader.search("li")
        reader.search("keeper")
        #expect(reader.isSearching)
        let deadline = Date().addingTimeInterval(10)
        while reader.isSearching, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(reader.searchResults.count == 3)
        #expect(reader.searchResults.allSatisfy { $0.snippet.lowercased().contains("keeper") })
    }

    @Test func snippetsDropCutWords() {
        #expect(BKPDFReaderViewModel.snippet("ls circled above the old\nlighthouse. The kee", match: "lighthouse")
                == "…circled above the old lighthouse. The…")
        #expect(BKPDFReaderViewModel.snippet("lighthouse keeper", match: "keeper") == "lighthouse keeper")
    }

    @Test func outlineBecomesContents() throws {
        let reader = try makeReader(try makePDF(), store: BKJSONReaderStore(directory: directory.appendingPathComponent("store")))
        let root = PDFOutline()
        for (index, label) in ["Opening", "Ending"].enumerated() {
            let item = PDFOutline()
            item.label = label
            item.destination = PDFDestination(page: try #require(reader.document.page(at: index * 2)), at: .zero)
            root.insertChild(item, at: index)
        }
        reader.document.outlineRoot = root
        #expect(reader.contentsEntries.map(\.label) == ["Opening", "Ending"])
        #expect(reader.contentsEntries.map(\.spineIndex) == [0, 2])
        #expect(reader.sectionTitle(forPage: 1) == "Opening")
        reader.document.outlineRoot = nil
        // Without an outline, marks are listed under the book's title.
        #expect(reader.sectionTitle(forPage: 1) == "sample")
    }

    @Test func identifiesFilesByContents() throws {
        let url = try makePDF()
        let copy = directory.appendingPathComponent("copy.pdf")
        try FileManager.default.copyItem(at: url, to: copy)
        #expect(BKPDFReaderViewBuilder.identifier(forPDFAt: url) == BKPDFReaderViewBuilder.identifier(forPDFAt: copy))
        #expect(BKPDFReaderViewBuilder.identifier(forPDFAt: url).hasPrefix("pdf-"))
        let notPDF = directory.appendingPathComponent("note.pdf")
        try Data("hello".utf8).write(to: notPDF)
        #expect(BKPDFReaderViewBuilder.build(url: notPDF) == nil)
    }
}
