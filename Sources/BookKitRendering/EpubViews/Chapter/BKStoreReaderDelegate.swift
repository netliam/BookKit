//
//  BKStoreReaderDelegate.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import BookKitCore

/// A `BKReaderCoordsProtocol` that persists everything into a store, so integrators don't need
/// their own delegate:
///
/// ```swift
/// let store = BKJSONReaderStore()
/// let position = await store.position(bookId: book.uniqueIdentifier)
/// BKReaderViewBuilder.build(book,
///                           spineIndex: position?.spineIndex ?? 0,
///                           initialCoords: position?.coords,
///                           delegate: BKStoreReaderDelegate(store: store))
/// ```
///
/// Reading positions go to `save(position:)`. Bookmarks, highlights and notes are `BKHighlight`s the
/// reader saves and deletes through `save(highlight:)` / `deleteHighlight(uuid:book:)`.
@MainActor
public final class BKStoreReaderDelegate: BKReaderCoordsProtocol {

    public typealias Store = BKHighlightStoreProtocol & BKReadingPositionStoreProtocol

    public let store: any Store
    /// The key records are stored under; `nil` uses the book's OPF identifier. Pass the same value
    /// as `BKReaderConfiguration.bookId`.
    public let bookId: String?

    public init(store: any Store, bookId: String? = nil) {
        self.store = store
        self.bookId = bookId
    }

    private func key(for book: BKEpubBook) -> String {
        bookId ?? book.uniqueIdentifier
    }

    public func handleCoords(book: BKEpubBook,
                             spineIndex: Int,
                             coords: String,
                             chapterURL: URL?,
                             isBookMark: Bool) {
        // The reader saves bookmarks itself (as `.bookMark` highlights); only positions are stored here.
        guard !isBookMark else { return }
        let chapterId = (chapterURL ?? book.chapterURL(forSpineIndex: spineIndex))?.lastPathComponent ?? ""
        let position = BKReadingPosition(bookId: key(for: book),
                                         spineIndex: spineIndex,
                                         coords: coords,
                                         chapterId: chapterId)
        Task {
            await store.save(position: position)
        }
    }

    public func save(highlight: BKHighlight) async {
        await store.save(highlight)
    }

    public func deleteHighlight(uuid: String, book: BKEpubBook) async {
        await store.delete(uuid: uuid)
    }

    public func highlights(for book: BKEpubBook) async -> [BKHighlight]? {
        await store.highlights(bookId: key(for: book))
    }

    public func highlights(for book: BKEpubBook, chapterId: String) async -> [BKHighlight]? {
        await store.highlights(bookId: key(for: book), chapterId: chapterId)
    }
}
