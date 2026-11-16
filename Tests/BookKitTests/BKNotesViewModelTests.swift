//
//  BKNotesViewModelTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import SwiftUI
import Testing
import BookKitCore
@testable import BookKitRendering

/// The note editor's quote and saving.
@MainActor
@Suite("Note editor")
struct BKNotesViewModelTests {

    @MainActor
    private final class RecordingContext: BKChapterReaderContextProtocol {
        let currentBook = BKEpubBook.mock
        let bookId = "book"
        var saved: [BKHighlight] = []

        func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> BKChapterJump? { nil }
        func showNote(highlight: BKHighlight) {}
        func save(highlight: BKHighlight) async { saved.append(highlight) }
        func deleteHighlight(uuid: String) async {}
        func highlights(for chapterId: String) async -> [BKHighlight] { [] }
    }

    private func makeViewModel(text: String = "  The quoted passage.\n", note: String = "",
                               context: RecordingContext) -> BKNotesViewModel {
        let highlight = BKHighlight(uuid: "n1", bookId: "book", chapterId: "c1.xhtml", spineIndex: 0,
                                    type: .note, text: text, coords: "", note: note, style: .underline)
        return BKNotesViewModel(highlight: highlight, readerContext: context,
                                userPreferences: BKUserPreferencesMock(),
                                appearance: BKReaderAppearance(theme: .original, isDark: false))
    }

    @Test("Shows the selected passage, trimmed")
    func quotesSelection() {
        let viewModel = makeViewModel(context: RecordingContext())
        #expect(viewModel.quotedText == "The quoted passage.")
    }

    @Test("Closing within the debounce still saves the note")
    func saveNowFlushesPendingEdit() async throws {
        let context = RecordingContext()
        let viewModel = makeViewModel(context: context)
        viewModel.note = "My thought"
        viewModel.noteDidChange("My thought")
        viewModel.saveNow()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(context.saved.map(\.note) == ["My thought"])

        // The cancelled debounce doesn't save it a second time.
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(context.saved.count == 1)
    }

    @Test("Closing without changes doesn't save")
    func saveNowWithoutChanges() async throws {
        let context = RecordingContext()
        let viewModel = makeViewModel(note: "Existing", context: context)
        viewModel.saveNow()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(context.saved.isEmpty)
    }
}
