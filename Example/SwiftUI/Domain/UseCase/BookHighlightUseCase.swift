//
//  BookHighlightUseCase.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import BookKit
import Foundation

protocol BookHighlightUseCaseProtocol {
    func saveHighlight(_ highlight: BKHighlight) throws
    func highlights(bookId: String) throws -> [BKHighlight]
    func highlights(bookId: String, chapterId: String) throws -> [BKHighlight]
    func deleteHighlight(uuid: String) throws
}

final class BookHighlightUseCase: BookHighlightUseCaseProtocol {

    private let repository: BookHighlightRepositoryProtocol

    init(repository: BookHighlightRepositoryProtocol) {
        self.repository = repository
    }

    func saveHighlight(_ highlight: BKHighlight) throws {
        try repository.saveHighlight(highlight)
    }

    func highlights(bookId: String) throws -> [BKHighlight] {
        try repository.highlights(bookId: bookId)
    }

    func highlights(bookId: String, chapterId: String) throws -> [BKHighlight] {
        try repository.highlights(bookId: bookId, chapterId: chapterId)
    }

    func deleteHighlight(uuid: String) throws {
        try repository.deleteHighlight(uuid: uuid)
    }
}
