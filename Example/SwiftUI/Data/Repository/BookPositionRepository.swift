//
//  BookPositionRepository.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 22/12/25.
//

import BookKit
import Foundation

protocol BookPositionRepositoryProtocol {
    func saveBookPosition(book: BKEpubBook,
                          spineIndex: Int,
                          coords: String,
                          chapterURL: URL,
                          markType: RBookMark.MarkType) throws
    func getBookPosition(book: BKEpubBook) throws -> EBookPositionEntity?
}

final class BookPositionRepository: BookPositionRepositoryProtocol {

    private let database: BookPositionDatabaseProtocol

    init(database: BookPositionDatabaseProtocol) {
        self.database = database
    }

    func saveBookPosition(book: BKEpubBook,
                          spineIndex: Int,
                          coords: String,
                          chapterURL: URL,
                          markType: RBookMark.MarkType) throws {
        try database.saveBookPosition(
            book: book,
            spineIndex: spineIndex,
            coords: coords,
            chapterURL: chapterURL,
            markType: markType
        )
    }

    func getBookPosition(book: BKEpubBook) throws -> EBookPositionEntity? {
        guard let dto = try database.getBookPosition(book: book) else {
            return nil
        }
        return dto
    }
}
