//
//  BookHighlightRepository.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import BookKit
import Foundation

protocol BookHighlightRepositoryProtocol {
    func saveHighlight(_ highlight: BKHighlight) throws
    func highlights(bookId: String) throws -> [BKHighlight]
    func highlights(bookId: String, chapterId: String) throws -> [BKHighlight]
    func deleteHighlight(uuid: String) throws
}

final class BookHighlightRepository: BookHighlightRepositoryProtocol {

    private let database: BookHighlightDatabaseProtocol

    init(database: BookHighlightDatabaseProtocol) {
        self.database = database
    }

    func saveHighlight(_ highlight: BKHighlight) throws {
        try database.saveHighlight(highlight)
    }

    func highlights(bookId: String) throws -> [BKHighlight] {
        try database.highlights(bookId: bookId)
    }

    func highlights(bookId: String, chapterId: String) throws -> [BKHighlight] {
        try database.highlights(bookId: bookId, chapterId: chapterId)
    }

    func deleteHighlight(uuid: String) throws {
        try database.deleteHighlight(uuid: uuid)
    }
}
