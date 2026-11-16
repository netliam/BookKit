//
//  BKProgressScrubberTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import BookKitCore
import BookKitParser
@testable import BookKitRendering

/// Mapping the progress scrubber's position to a page of the book and back.
@Suite("Progress scrubber")
struct BKProgressScrubberTests {

    private typealias Target = BKReaderViewModel.ScrubTarget
    /// Three chapters: 4, 0 (an empty cover page that lays out to nothing) and 6 pages.
    private let counts = [0: 4, 1: 0, 2: 6]

    @Test func endsOpenTheFirstAndLastPages() {
        #expect(BKReaderViewModel.scrubTarget(fraction: 0, counts: counts, chapterCount: 3)
                == Target(spineIndex: 0, pageIndex: 0, bookPage: 1, bookTotal: 10))
        #expect(BKReaderViewModel.scrubTarget(fraction: 1, counts: counts, chapterCount: 3)
                == Target(spineIndex: 2, pageIndex: 5, bookPage: 10, bookTotal: 10))
        // Out of range values (a slider overshoot) are clamped.
        #expect(BKReaderViewModel.scrubTarget(fraction: 1.4, counts: counts, chapterCount: 3).bookPage == 10)
    }

    @Test func everyPageIsReachableAndChaptersWithoutPagesAreSkipped() {
        var seen: [Target] = []
        for page in 1...10 {
            let fraction = Double(page - 1) / 9
            let target = BKReaderViewModel.scrubTarget(fraction: fraction, counts: counts, chapterCount: 3)
            #expect(target.bookPage == page)
            seen.append(target)
        }
        #expect(seen[3] == Target(spineIndex: 0, pageIndex: 3, bookPage: 4, bookTotal: 10))
        #expect(seen[4] == Target(spineIndex: 2, pageIndex: 0, bookPage: 5, bookTotal: 10))
        #expect(!seen.contains { $0.spineIndex == 1 })
    }

    @Test func movesByChapterUntilTheBookIsCounted() {
        let targets = [0, 0.4, 0.7, 1].map {
            BKReaderViewModel.scrubTarget(fraction: $0, counts: nil, chapterCount: 3)
        }
        #expect(targets.map(\.spineIndex) == [0, 1, 2, 2])
        #expect(targets.allSatisfy { $0.pageIndex == 0 && $0.bookPage == nil })
    }
}

/// The "Back to Page N" button after a jump.
@MainActor
@Suite("Back to previous page")
struct BKBackPositionTests {

    @Test func noBackButtonBeforeAnyJump() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let reader = BKReaderViewModel(book: try BKEpubParser.parse(from: url),
                                       spineIndex: 0,
                                       userPreferencesProtocol: BKUserPreferencesMock(),
                                       delegate: nil)
        #expect(reader.backPosition == nil)
        #expect(reader.backButtonTitle == nil)
    }

    @Test func jumpRemembersThePageItLeft() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try BKEpubParser.parse(from: url)
        let reader = BKReaderViewModel(book: book,
                                       spineIndex: 0,
                                       userPreferencesProtocol: BKUserPreferencesMock(),
                                       delegate: nil)
        // On page 2 of 3 of the first chapter, at a known position.
        reader.handle(.currentPage(index: 2, totalPages: 3, spineIndex: 0), chapterURL: nil)
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0000001>0000003|0000012", isBookMark: false),
                      chapterURL: nil)
        #expect(reader.hasPagePosition)

        let lastChapter = book.spine.count - 1
        reader.jump(to: .init(spineIndex: lastChapter, pageIndex: 0, bookPage: nil, bookTotal: nil))
        let back = try #require(reader.backPosition)
        #expect(back.spineIndex == 0)
        #expect(back.pageIndex == 1)
        #expect(back.coords == "0000001>0000003|0000012")

        reader.goBack()
        #expect(reader.backPosition == nil)
    }

    @Test func afterARelayoutTheBackButtonNamesTheChapter() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try BKEpubParser.parse(from: url)
        let reader = BKReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: BKUserPreferencesMock(), delegate: nil)
        reader.handle(.currentPage(index: 1, totalPages: 3, spineIndex: 0), chapterURL: nil)
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0000001>0000001|0000000", isBookMark: false),
                      chapterURL: nil)
        reader.jump(to: .init(spineIndex: 0, pageIndex: 2, bookPage: nil, bookTotal: nil))
        // The reader reports the page it landed on.
        reader.handle(.currentPage(index: 3, totalPages: 3, spineIndex: 0), chapterURL: nil)
        let title = try #require(reader.backButtonTitle)
        reader.textLayout.lineSpacing = .loose
        // No page number from the old layout; still somewhere to go back to.
        let relaidOut = try #require(reader.backButtonTitle)
        #expect(!relaidOut.contains("Page"))
        #expect(title.hasPrefix("Back to"))
    }

    @Test func aReloadedChapterResumesAtTheLastPosition() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try BKEpubParser.parse(from: url)
        let reader = BKReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: BKUserPreferencesMock(), delegate: nil)
        let chapterURL = try #require(book.chapterURL(forSpineIndex: 0))
        #expect(reader.consumeInitialJump(for: 0, chapterURL: chapterURL) == nil)
        reader.handle(.coordsFirstNodeOfPage(orientation: .vertical, spineIndex: 0, coords: "0000001>0000002|0000000", isBookMark: false),
                      chapterURL: nil)
        #expect(reader.consumeInitialJump(for: 0, chapterURL: chapterURL) == .coords("0000001>0000002|0000000"))
    }
}

/// The delegate hears where the reader is in the whole book, not just the chapter.
@MainActor
@Suite("Whole-book progress")
struct BKReaderProgressTests {

    private final class Delegate: BKReaderCoordsProtocol {
        var progress: [BKReaderProgress] = []
        func handleCoords(book: BKEpubBook, spineIndex: Int, coords: String, chapterURL: URL?, isBookMark: Bool) {}
        func handleProgress(book: BKEpubBook, progress: BKReaderProgress) { self.progress.append(progress) }
    }

    @Test func reportedAfterEachPageTurnEstimatedUntilCounted() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try BKEpubParser.parse(from: url)
        let delegate = Delegate()
        let reader = BKReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: BKUserPreferencesMock(), delegate: delegate)
        let chapterURL = try #require(book.chapterURL(forSpineIndex: 0))
        reader.handle(.currentPage(index: 3, totalPages: 5, spineIndex: 0), chapterURL: chapterURL)
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0000001>0000003|0000000",
                                             isBookMark: false), chapterURL: chapterURL)
        let progress = try #require(delegate.progress.last)
        #expect(progress.coords == "0000001>0000003|0000000")
        #expect(progress.page == nil && progress.totalPages == nil)
        // Not counted yet: two of five pages into the first of the book's chapters.
        #expect(abs(progress.fraction - (2.0 / 5.0) / Double(book.spine.count)) < 0.0001)

        // Bookmarks aren't page turns.
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "x", isBookMark: true),
                      chapterURL: chapterURL)
        #expect(delegate.progress.count == 1)
    }
}
