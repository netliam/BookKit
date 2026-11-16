//
//  BKWebViewModel.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 26/11/25.
//

import Foundation
import BookKitCore

@MainActor
final class BKWebViewModel: BKWebViewModelProtocol {

    var refresh: (() -> Void)?

    private let router: BKWebViewRouterProtocol

    init(router: BKWebViewRouterProtocol) {
        self.router = router
    }

    func showNoote(highlight: BKHighlight) {
        router.showNoote(highlight: highlight)
    }

    func searchBook(for text: String) {
        router.searchBook(for: text)
    }

    func openLink(_ url: URL) {
        router.openLink(url)
    }

    func saveHighlight(_ highlight: BKHighlight) async {
        await router.saveHighlight(highlight)
    }

    func loadHighlights() async -> [BKHighlight] {
        await router.loadHighlights()
    }

    func deleteHighlight(uuid: String) async {
        await router.deleteHighlight(uuid: uuid)
    }

    var currentBookId: String { router.currentBookId }
    var currentChapterId: String { router.currentChapterId }
    var currentSpineIndex: Int { router.currentSpineIndex }
    var currentBook: BKEpubBook? { router.currentBook }
    var configuration: BKReaderConfiguration { router.configuration }
}
