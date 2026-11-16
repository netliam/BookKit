//
//  MainViewModel.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 5/2/26.
//

import Combine
import BookKit
import PDFKit
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {

    @Published var books: [EBookEntity] = []
    @Published var selectedEbook: BKEpubBook?
    @Published var errorMsg: String?
    @Published var isPickerPresented = false

    private let useCase: UseCaseProtocol

    init(useCase: UseCaseProtocol) {
        self.useCase = useCase
    }

    var highlightStore: any BKHighlightStoreProtocol {
        useCase.highlightStore
    }

    /// Reading positions of PDFs and comics (EPUB positions are kept in Realm by `handleCoords`).
    let pdfPositionStore = BKJSONReaderStore()
}

// MARK: - Methods

extension MainViewModel {
    func loadBooks() {
        do {
            self.books = try useCase.bookFile.getBookList()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    func fileImporterResult(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importBook(from: url)
            errorMsg = nil
        case .failure(let error):
            errorMsg = "\(error)"
        }
    }

    func getEpubBook(book: EBookEntity) -> BKEpubBook? {
        guard let url = book.basePath else { return nil }
        return try? BKEpubParser.parse(from: url)
    }

    func initialBookPosition(for book: BKEpubBook) -> EBookPositionEntity? {
        try? useCase.bookPosition.getBookPosition(book: book)
    }

    func bookHighlights(for book: BKEpubBook) async -> [BKHighlight] {
        await highlightStore.highlights(bookId: book.uniqueIdentifier)
    }
}

// MARK: - DC Reader Coords Protocols

extension MainViewModel: BKReaderCoordsProtocol {
    func handleCoords(
        book: BKEpubBook,
        spineIndex: Int,
        coords: String,
        chapterURL: URL?,
        isBookMark: Bool
    ) {
        // Bookmarks are saved by the reader through save(highlight:); only positions are stored here.
        guard let chapterURL, !isBookMark else { return }
        print(
            """
            spineIndex: \(spineIndex) -
            coords: \(coords) -
            chapterURL: \(chapterURL.path) -
            isBookMark: \(isBookMark)
            """
        )
        try? useCase.bookPosition.saveBookPosition(
            book: book,
            spineIndex: spineIndex,
            coords: coords,
            chapterURL: chapterURL,
            markType: .lastPosition
        )
    }

    func highlights(for book: BKEpubBook) async -> [BKHighlight]? {
        await highlightStore.highlights(bookId: book.uniqueIdentifier)
    }

    func highlights(for book: BKEpubBook, chapterId: String) async -> [BKHighlight]? {
        await highlightStore.highlights(bookId: book.uniqueIdentifier, chapterId: chapterId)
    }

    func save(highlight: BKHighlight) async {
        await highlightStore.save(highlight)
    }

    func deleteHighlight(uuid: String, book: BKEpubBook) async {
        await highlightStore.delete(uuid: uuid)
    }
}

// MARK: - Private

private extension MainViewModel {
    func importBook(from url: URL) {
        switch BKBookFormat(fileURL: url) {
        case .pdf:
            importPDF(from: url)
            return
        case .comic:
            importComic(from: url)
            return
        default:
            break
        }
        do {
            let stagingBase = FileHelper.shared.getTempFolder()
                .appendingPathComponent(FileHelper.Constants.tempFolder, isDirectory: true)
            let stagingRoot = stagingBase
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            defer {
                try? FileManager.default.removeItem(at: stagingRoot)
                FileHelper.shared.clearTempSubfolder()
            }

            let unzipRoot: URL
            switch BKBookFormat(fileURL: url) {
            case .plainText, .markdown, .mobi:
                // Text, Markdown and Kindle books are converted into an EPUB-style folder that the
                // reader opens as usual.
                let needsSecurityAccess = url.startAccessingSecurityScopedResource()
                defer { if needsSecurityAccess { url.stopAccessingSecurityScopedResource() } }
                if BKBookFormat(fileURL: url) == .mobi {
                    _ = try BKMobiConverter.convert(url, to: stagingRoot)
                } else {
                    _ = try BKTextBookConverter.convert(url, to: stagingRoot)
                }
                unzipRoot = stagingRoot
            default:
                unzipRoot = try EpubFileManager.shared.prepareBookFiles(
                    epubFile: url,
                    destinationRoot: stagingRoot
                )
            }

            let parsedBook = try BKEpubParser.parse(from: unzipRoot)
            let finalRoot = FileHelper.shared.bookDirectory(for: parsedBook.uniqueIdentifier)

            if FileManager.default.fileExists(atPath: finalRoot.path) {
                try FileManager.default.removeItem(at: finalRoot)
            }
            try FileManager.default.moveItem(at: unzipRoot, to: finalRoot)

            let persistedBook = try BKEpubParser.parse(from: finalRoot)
            try useCase.bookFile.saveBook(book: persistedBook)
            loadBooks()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// Comics are read straight from the archive: it's copied into the book's folder, with page 1 as the cover.
    func importComic(from url: URL) {
        let needsSecurityAccess = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let book = try BKComicBook(url: url)
            let folder = FileHelper.shared.bookDirectory(for: book.identifier)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent("book.cbz"))

            var coverPath = ""
            if let image = UIImage(data: try book.imageData(page: 0)),
               let png = image.preparingThumbnail(of: CGSize(width: 400, height: 400 * image.size.height / max(image.size.width, 1)))?.pngData() {
                try png.write(to: folder.appendingPathComponent("cover.png"))
                coverPath = "cover.png"
            }
            try useCase.bookFile.saveBook(uuid: book.identifier, title: book.title,
                                          author: book.authors.joined(separator: ", "),
                                          format: BKBookFormat.comic.rawValue, coverPath: coverPath)
            loadBooks()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// PDFs are read straight from the file: it's copied into the book's folder, with page 1 as the cover.
    func importPDF(from url: URL) {
        let needsSecurityAccess = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let document = PDFDocument(url: url), !document.isLocked else {
                errorMsg = "This PDF can't be opened (it may be password protected).".localized()
                return
            }
            let bookId = BKPDFReaderViewBuilder.identifier(forPDFAt: url)
            let folder = FileHelper.shared.bookDirectory(for: bookId)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent("book.pdf"))

            var coverPath = ""
            if let page = document.page(at: 0),
               let png = page.thumbnail(of: CGSize(width: 400, height: 600), for: .mediaBox).pngData() {
                try png.write(to: folder.appendingPathComponent("cover.png"))
                coverPath = "cover.png"
            }
            let attributes = document.documentAttributes ?? [:]
            let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? url.deletingPathExtension().lastPathComponent
            let author = attributes[PDFDocumentAttribute.authorAttribute] as? String ?? ""
            try useCase.bookFile.saveBook(uuid: bookId, title: title, author: author,
                                          format: BKBookFormat.pdf.rawValue, coverPath: coverPath)
            loadBooks()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
