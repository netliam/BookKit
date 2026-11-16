//
//  BookFileUseCase.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 19/1/26.
//

import BookKit
import Foundation

protocol BookFileUseCaseProtocol {
    func saveBook(book: BKEpubBook) throws
    func saveBook(uuid: String, title: String, author: String, format: String, coverPath: String) throws
    func getBookList() throws -> [EBookEntity]
    func getBook(uuid: String) throws -> EBookEntity
    func deleteBook(uuid: String) throws
}

final class BookFileUseCase: BookFileUseCaseProtocol {

    private let repository: BookFileRepositoryProtocol

    init(repository: BookFileRepositoryProtocol) {
        self.repository = repository
    }

    func saveBook(book: BKEpubBook) throws {
        try repository.saveBook(book: book)
    }

    func saveBook(uuid: String, title: String, author: String, format: String, coverPath: String) throws {
        try repository.saveBook(uuid: uuid, title: title, author: author, format: format, coverPath: coverPath)
    }

    func getBookList() throws -> [EBookEntity] {
        try repository.getBookList()
    }

    func getBook(uuid: String) throws -> EBookEntity {
        try repository.getBook(uuid: uuid)
    }

    func deleteBook(uuid: String) throws {
        try repository.deleteBook(uuid: uuid)
    }
}
