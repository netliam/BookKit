//
//  EBookEntity.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 5/2/26.
//

import Foundation

struct EBookEntity {
    let uuid: String
    let title: String
    let author: String
    let coverPath: String
    let language: String
    let publisher: String
    let bookVersion: String
    let bookDate: String
    let descriptionHTML: String
    let createdAt: Int64
    let updatedAt: Int64
    /// `BKBookFormat` raw value; books read as an EPUB folder (EPUB, text, Markdown) store "epub" or "".
    let format: String

    var basePath: URL? {
        FileHelper.shared.bookDirectory(for: uuid)
    }

    var isPDF: Bool { format == "pdf" }
    var isComic: Bool { format == "comic" }

    /// The archive, for comic books (kept as `book.cbz` in the book's folder).
    var comicURL: URL? {
        basePath?.appendingPathComponent("book.cbz")
    }

    /// The PDF file, for PDF books (kept as `book.pdf` in the book's folder).
    var pdfURL: URL? {
        basePath?.appendingPathComponent("book.pdf")
    }
}
