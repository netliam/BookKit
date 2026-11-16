//
//  BKReaderProtocols.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 6/2/26.
//

import Foundation
import BookKitCore

@MainActor
public protocol BKReaderCoordsProtocol {
    func handleCoords(book: BKEpubBook,
                      spineIndex: Int,
                      coords: String,
                      chapterURL: URL?,
                      isBookMark: Bool)

    /// Where the reader is in the whole book, after each `handleCoords` for a page turn (not bookmarks).
    func handleProgress(book: BKEpubBook, progress: BKReaderProgress)

    func save(highlight: BKHighlight) async
    func deleteHighlight(uuid: String, book: BKEpubBook) async
    func highlights(for book: BKEpubBook) async -> [BKHighlight]?
    func highlights(for book: BKEpubBook, chapterId: String) async -> [BKHighlight]?
}

public extension BKReaderCoordsProtocol {
    func handleProgress(book: BKEpubBook, progress: BKReaderProgress) {}

    func save(highlight: BKHighlight) async {}

    func deleteHighlight(uuid: String, book: BKEpubBook) async {}

    func highlights(for book: BKEpubBook) async -> [BKHighlight]? {
        nil
    }

    func highlights(for book: BKEpubBook, chapterId: String) async -> [BKHighlight]? {
        nil
    }
}

/// The reader's place in the whole book, as the progress bar shows it ("11 of 39").
public struct BKReaderProgress: Equatable, Sendable {
    public let spineIndex: Int
    public let coords: String
    /// Fraction of the book read, 0...1: `page / totalPages` once counted, else estimated from
    /// chapters (the chapter index plus the fraction of the chapter read).
    public let fraction: Double
    /// Whole-book page and page count, once the book has been counted (`nil` until then). They
    /// depend on the text size, layout and window size.
    public let page: Int?
    public let totalPages: Int?

    public init(spineIndex: Int, coords: String, fraction: Double, page: Int?, totalPages: Int?) {
        self.spineIndex = spineIndex
        self.coords = coords
        self.fraction = fraction
        self.page = page
        self.totalPages = totalPages
    }
}

/// Where to move inside a chapter once it has loaded.
enum BKChapterJump: Equatable {
    /// A saved location (position, highlight or bookmark).
    case coords(String)
    /// The n-th match of a search query, which is also highlighted.
    case search(query: String, occurrence: Int)
    /// The element with this id, from a table-of-contents link.
    case fragment(String)
    /// A page (0-based) of the chapter, from the progress scrubber.
    case page(Int)
}

@MainActor
protocol BKChapterReaderContextProtocol: AnyObject {
    var currentBook: BKEpubBook { get }
    var bookId: String { get }
    func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> BKChapterJump?
    func showNote(highlight: BKHighlight)
    func save(highlight: BKHighlight) async
    func deleteHighlight(uuid: String) async
    func highlights(for chapterId: String) async -> [BKHighlight]
    var configuration: BKReaderConfiguration { get }
}

extension BKChapterReaderContextProtocol {
    var configuration: BKReaderConfiguration { BKReaderConfiguration() }
}
