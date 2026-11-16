//
//  BookHighlightStore.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import BookKit
import Foundation

@MainActor
final class BookHighlightStore: BKHighlightStoreProtocol {

    private let useCase: BookHighlightUseCaseProtocol

    init(useCase: BookHighlightUseCaseProtocol) {
        self.useCase = useCase
    }

    func save(_ highlight: BKHighlight) async {
        try? useCase.saveHighlight(highlight)
    }

    func highlights(bookId: String) async -> [BKHighlight] {
        (try? useCase.highlights(bookId: bookId)) ?? []
    }

    func highlights(bookId: String, chapterId: String) async -> [BKHighlight] {
        (try? useCase.highlights(bookId: bookId, chapterId: chapterId)) ?? []
    }

    func delete(uuid: String) async {
        try? useCase.deleteHighlight(uuid: uuid)
    }
}
