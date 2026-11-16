//
//  BKNotesViewBuilder.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 10/11/25.
//

import Foundation
import BookKitCore

final class BKNotesViewBuilder {
    @MainActor
    func build(highlight: BKHighlight,
               readerContext: any BKChapterReaderContextProtocol,
               userPreferences: BKUserPreferencesProtocol,
               appearance: BKReaderAppearance) -> BKNotesView {
        let viewModel = BKNotesViewModel(
            highlight: highlight,
            readerContext: readerContext,
            userPreferences: userPreferences,
            appearance: appearance
        )
        return BKNotesView(viewModel: viewModel)
    }
}

final class BKNotesViewBuilderMock {
    @MainActor
    func build() -> BKNotesView {
        let highlight = BKHighlight(
            uuid: "preview-uuid",
            bookId: "preview-book",
            chapterId: "chapter01.xhtml",
            spineIndex: 0,
            type: .note,
            text: "Selected text for preview",
            coords: ""
        )
        let viewModel = BKNotesViewModel(
            highlight: highlight,
            readerContext: BKNotesPreviewContext(),
            userPreferences: BKUserPreferencesMock(),
            appearance: BKReaderAppearance(theme: .original, isDark: false)
        )
        return BKNotesView(viewModel: viewModel)
    }
}

@MainActor
private final class BKNotesPreviewContext: BKChapterReaderContextProtocol {
    let currentBook = BKEpubBook.mock
    let bookId = "preview-book"

    func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> BKChapterJump? { nil }
    func showNote(highlight: BKHighlight) {}
    func save(highlight: BKHighlight) async {}
    func deleteHighlight(uuid: String) async {}
    func highlights(for chapterId: String) async -> [BKHighlight] { [] }
}
