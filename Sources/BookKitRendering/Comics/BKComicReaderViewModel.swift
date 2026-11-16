//
//  BKComicReaderViewModel.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import ImageIO
import SwiftUI
import BookKitCore

/// State of the comic reader: page, bookmarks and decoded page images.
@MainActor
final class BKComicReaderViewModel: ObservableObject {

    let book: BKComicBook
    let bookId: String
    private let highlightStore: BKHighlightStoreProtocol?
    private let positionStore: BKReadingPositionStoreProtocol?

    @Published private(set) var pageIndex = 0
    @Published var isChromeVisible = false
    @Published var showPages = false
    @Published var showShare = false
    @Published private(set) var bookmarks: [BKHighlight] = []

    /// Moves the pager; set by it.
    var showPage: ((Int, Bool) -> Void)?
    private let images = NSCache<NSNumber, UIImage>()
    private var positionTask: Task<Void, Never>?

    init(book: BKComicBook,
         bookId: String,
         highlightStore: BKHighlightStoreProtocol?,
         positionStore: BKReadingPositionStoreProtocol?) {
        self.book = book
        self.bookId = bookId
        self.highlightStore = highlightStore
        self.positionStore = positionStore
        images.countLimit = 8
    }

    var pageCount: Int { book.pages.count }

    var pageText: String {
        String(format: L("%lld of %lld"), pageIndex + 1, pageCount)
    }

    static func coords(page: Int) -> String { "comic|\(page)" }

    static func page(fromCoords coords: String) -> Int? {
        let parts = coords.split(separator: "|")
        guard parts.count == 2, parts[0] == "comic" else { return nil }
        return Int(parts[1])
    }

    /// Loads bookmarks and returns the saved page.
    func load() async -> Int {
        bookmarks = (await highlightStore?.highlights(bookId: bookId) ?? []).filter { $0.type == .bookMark }
        if let position = await positionStore?.position(bookId: bookId),
           let page = Self.page(fromCoords: position.coords), book.pages.indices.contains(page) {
            pageIndex = page
            return page
        }
        return 0
    }

    func pageDidChange(to page: Int) {
        guard page != pageIndex else { return }
        pageIndex = page
        isChromeVisible = false
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.positionStore?.save(position: BKReadingPosition(bookId: self.bookId, spineIndex: page,
                                                                       coords: Self.coords(page: page),
                                                                       chapterId: "page-\(page + 1)"))
        }
    }

    func go(toPage page: Int) {
        let target = min(max(0, page), pageCount - 1)
        showPage?(target, target != pageIndex)
        pageDidChange(to: target)
    }

    // MARK: - Bookmarks

    var isCurrentPageBookmarked: Bool { isBookmarked(pageIndex) }

    func isBookmarked(_ page: Int) -> Bool {
        bookmarks.contains { $0.spineIndex == page }
    }

    func toggleBookmark() {
        if let existing = bookmarks.first(where: { $0.spineIndex == pageIndex }) {
            bookmarks.removeAll { $0.uuid == existing.uuid }
            Task { await highlightStore?.delete(uuid: existing.uuid) }
            return
        }
        let page = pageIndex
        let bookmark = BKHighlight(uuid: UUID().uuidString, bookId: bookId, chapterId: "page-\(page + 1)",
                                   spineIndex: page, type: .bookMark, text: "",
                                   coords: Self.coords(page: page), chapterTitle: book.title)
        bookmarks.append(bookmark)
        Task { await highlightStore?.save(bookmark) }
    }

    // MARK: - Images

    /// Page `index`, decoded at most `maxPixelSize` on its longer side (keeps memory in check).
    func image(page index: Int, maxPixelSize: CGFloat) async -> UIImage? {
        let key = NSNumber(value: index * 10_000 + Int(maxPixelSize))
        if let cached = images.object(forKey: key) { return cached }
        let book = book
        let image = await Task.detached(priority: .userInitiated) {
            guard let data = try? book.imageData(page: index) else { return UIImage?.none }
            return Self.downsample(data, maxPixelSize: maxPixelSize)
        }.value
        if let image { images.setObject(image, forKey: key) }
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
