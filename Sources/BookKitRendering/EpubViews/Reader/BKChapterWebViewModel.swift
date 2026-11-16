//
//  BKChapterWebViewModel.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 2/11/25.
//

import SwiftUI
import BookKitCore

@MainActor
final class BKChapterWebViewModel: ObservableObject {

    var showNotes: Bool = false
    weak var coordinator: BKChapterWebView.Coordinator?

    /// Absolute file URL of the HTML/XHTML chapter.
    let chapterURL: URL
    /// Directory granting read access to all relative resources (usually `opfDirectoryURL`).
    let readAccessURL: URL
    /// Index of the spine that this view represents (used for disambiguating async callbacks).
    let spineIndex: Int
    let userPreferences: BKUserPreferencesProtocol
    let appearance: BKReaderAppearance
    let onAction: (BKChapterViewAction) -> Void
    private let readerContext: any BKChapterReaderContextProtocol
    private var hasConsumedInitialCoords = false

    init(chapterURL: URL,
         readAccessURL: URL,
         spineIndex: Int,
         userPreferences: BKUserPreferencesProtocol,
         appearance: BKReaderAppearance,
         readerContext: any BKChapterReaderContextProtocol,
         onAction: @escaping (BKChapterViewAction) -> Void) {
        self.chapterURL = chapterURL
        self.readAccessURL = readAccessURL
        self.spineIndex = spineIndex
        self.userPreferences = userPreferences
        self.appearance = appearance
        self.readerContext = readerContext
        self.onAction = onAction
    }

    func consumeInitialJump() -> BKChapterJump? {
        guard hasConsumedInitialCoords == false else { return nil }
        hasConsumedInitialCoords = true
        return readerContext.consumeInitialJump(for: spineIndex, chapterURL: chapterURL)
    }
}

extension BKChapterWebViewModel: BKWebViewRouterProtocol {

    func showNoote(highlight: BKHighlight) {
        onAction(.showNote(highlight: highlight))
    }

    func searchBook(for text: String) {
        onAction(.searchBook(query: text))
    }

    func openLink(_ url: URL) {
        onAction(.openLink(url))
    }

    func saveHighlight(_ highlight: BKHighlight) async {
        await readerContext.save(highlight: highlight)
    }

    func loadHighlights() async -> [BKHighlight] {
        await readerContext.highlights(for: currentChapterId)
    }

    func deleteHighlight(uuid: String) async {
        await readerContext.deleteHighlight(uuid: uuid)
    }

    var currentBookId: String { readerContext.bookId }
    var currentChapterId: String { chapterURL.lastPathComponent }
    var currentSpineIndex: Int { spineIndex }
    var currentBook: BKEpubBook? { readerContext.currentBook }
    var configuration: BKReaderConfiguration { readerContext.configuration }
    var isFixedLayout: Bool { readerContext.currentBook.isFixedLayout(spineIndex: spineIndex) }

    func updateCurrentPage(target: Int?) {
        coordinator?.updateCurrentPageInternal(target: target)
    }

    func saveBookmark() {
        coordinator?.saveBookMark()
    }

    func jump(to jump: BKChapterJump) {
        coordinator?.jump(to: jump)
    }

    /// Whether the chapter has loaded and been paginated (see `consumeInitialJump`).
    var isLaidOut: Bool { coordinator?.isLaidOut ?? false }

    func selectedText() async -> String? {
        await coordinator?.lazyWebView?.selectedText()
    }

    /// Page (0-based) of this chapter that a saved position falls on, in the scrolling layout.
    func pageIndex(forCoords coords: String) async -> Int? {
        guard let webView = coordinator?.lazyWebView, !coords.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: [coords]),
              let literal = String(data: data, encoding: .utf8) else { return nil }
        let raw = try? await webView.evaluateJavaScriptAsync("String(Math.max(0, getPageFromCoordsVertical(\(literal)[0])))")
        return Int(raw ?? "")
    }
}
