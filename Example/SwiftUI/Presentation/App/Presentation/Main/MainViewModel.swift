//
//  MainViewModel.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 5/2/26.
//

import Combine
import BookKit
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
            case .plainText, .markdown:
                // Text and Markdown are converted into an EPUB-style folder that the reader opens as usual.
                let needsSecurityAccess = url.startAccessingSecurityScopedResource()
                defer { if needsSecurityAccess { url.stopAccessingSecurityScopedResource() } }
                _ = try BKTextBookConverter.convert(url, to: stagingRoot)
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
}
