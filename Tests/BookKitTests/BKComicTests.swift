//
//  BKComicTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import Testing
import UIKit
@testable import BookKitCore
@testable import BookKitRendering

private func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
}

@Suite("ZIP archive")
struct BKZipArchiveTests {

    @Test func readsStoredAndDeflatedEntries() throws {
        let archive = try BKZipArchive(url: try fixture("Sample.cbz"))
        #expect(archive.entries.map(\.path).contains("pages/page10.png"))
        let deflated = try archive.data(at: "pages/page1.png")
        let stored = try archive.data(at: "pages/page2.png")
        // Both decode to the PNGs that were written.
        #expect(deflated.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(stored.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(UIImage(data: deflated)?.size == CGSize(width: 40, height: 60))
        let info = String(decoding: try archive.data(at: "ComicInfo.xml"), as: UTF8.self)
        #expect(info.contains("<Series>Harbour Tales</Series>"))
        #expect(throws: BKZipArchive.ArchiveError.missingEntry("nope")) { try archive.data(at: "nope") }
    }

    @Test func extractsEverything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try BKZipArchive(url: try fixture("Sample.cbz")).extractAll(to: directory)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pages/page10.png").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ComicInfo.xml").path))
    }

    @Test func refusesPathsOutsideTheFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try BKZipArchive(url: try fixture("Traversal.zip"))
        #expect(throws: BKZipArchive.ArchiveError.self) { try archive.extractAll(to: directory.appendingPathComponent("out")) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("evil.txt").path))
    }

    @Test func rejectsFilesThatArentZips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cbz")
        try Data("not a zip at all, just some text".utf8).write(to: url)
        #expect(throws: BKZipArchive.ArchiveError.notAZipFile) { try BKZipArchive(url: url) }
    }
}

@Suite("Comic book")
struct BKComicBookTests {

    @Test func pagesInNaturalOrderWithoutJunk() throws {
        let book = try BKComicBook(url: try fixture("Sample.cbz"))
        #expect(book.pages == ["pages/page1.png", "pages/page2.png", "pages/page10.png"])
        #expect(book.title == "Harbour Tales: The Lantern")
        #expect(book.authors == ["Ana Writer", "Ben Co", "Cy Artist"])
        #expect(book.readsRightToLeft)
        #expect(book.identifier.hasPrefix("comic-"))
        #expect(UIImage(data: try book.imageData(page: 2)) != nil)
    }

    @Test func comicInfoFallbacks() {
        var info = BKComicInfo()
        #expect(info.displayTitle == nil)
        info.fields = ["Series": "Tides", "Number": "7"]
        #expect(info.displayTitle == "Tides #7")
        #expect(!info.readsRightToLeft)
        #expect(BKBookFormat(fileURL: URL(fileURLWithPath: "/x/Comic.CBZ")) == .comic)
    }
}

@MainActor
@Suite("Comic reader")
struct BKComicReaderTests {

    @Test func bookmarksPositionAndImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BKJSONReaderStore(directory: directory)
        let book = try BKComicBook(url: try fixture("Sample.cbz"))
        let reader = BKComicReaderViewModel(book: book, bookId: book.identifier, highlightStore: store, positionStore: store)
        #expect(await reader.load() == 0)

        reader.go(toPage: 2)
        #expect(reader.pageText == "3 of 3")
        reader.toggleBookmark()
        #expect(reader.isBookmarked(2))

        var position = await store.position(bookId: book.identifier)
        let deadline = Date().addingTimeInterval(5)
        while position == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            position = await store.position(bookId: book.identifier)
        }
        #expect(position?.coords == "comic|2")

        // A new reader opens on the saved page with the bookmark.
        let reopened = BKComicReaderViewModel(book: book, bookId: book.identifier, highlightStore: store, positionStore: store)
        #expect(await reopened.load() == 2)
        #expect(reopened.isBookmarked(2))

        let shared = BKShareFile.named(book.fileURL, title: book.title)
        #expect(shared.lastPathComponent == "Harbour Tales- The Lantern.cbz")
        #expect(FileManager.default.contentsEqual(atPath: shared.path, andPath: book.fileURL.path))

        let image = try #require(await reader.image(page: 0, maxPixelSize: 30))
        #expect(max(image.size.width, image.size.height) <= 30)
    }
}
