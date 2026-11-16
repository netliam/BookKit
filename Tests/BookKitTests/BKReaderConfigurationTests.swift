//
//  BKReaderConfigurationTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import UIKit
import BookKitCore
import BookKitParser
@testable import BookKitRendering

/// What a host app sets through `BKReaderConfiguration`.
@MainActor
@Suite("Reader configuration")
struct BKReaderConfigurationTests {

    private func book() throws -> BKEpubBook {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        return try BKEpubParser.parse(from: url)
    }

    @Test func hostBookIdReplacesTheOPFIdentifier() throws {
        let book = try book()
        var configuration = BKReaderConfiguration()
        #expect(BKReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: BKUserPreferencesMock(),
                                  delegate: nil).bookId == book.uniqueIdentifier)
        configuration.bookId = "bow-42"
        let reader = BKReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: BKUserPreferencesMock(),
                                       delegate: nil, configuration: configuration)
        #expect(reader.bookId == "bow-42")
    }

    @Test func storeDelegateUsesTheHostBookId() async throws {
        let book = try book()
        let store = BKJSONReaderStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let delegate = BKStoreReaderDelegate(store: store, bookId: "bow-42")
        let chapter = try #require(book.chapterURL(forSpineIndex: 0))
        delegate.handleCoords(book: book, spineIndex: 0, coords: "0000001>0000000", chapterURL: chapter, isBookMark: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await store.position(bookId: "bow-42")?.coords == "0000001>0000000")
        #expect(await store.position(bookId: book.uniqueIdentifier) == nil)
    }

    @Test func externalLinksGoToTheHost() throws {
        var opened: URL?
        var configuration = BKReaderConfiguration()
        configuration.onOpenExternalURL = { opened = $0 }
        let reader = BKReaderViewModel(book: try book(), spineIndex: 0, userPreferencesProtocol: BKUserPreferencesMock(),
                                       delegate: nil, configuration: configuration)
        reader.openLink(URL(string: "https://example.com/a")!)
        #expect(opened?.absoluteString == "https://example.com/a")
    }

    @Test func hostFontIsLoadedAndApplied() throws {
        let file = URL(fileURLWithPath: "/fonts/Bow Serif.ttf")
        let font = BKReaderFont(name: "Bow Serif", cssFamily: "BowSerif", files: [file])
        #expect(font.css.contains(#"@font-face { font-family: "BowSerif"; src: url("file:///fonts/Bow%20Serif.ttf"); }"#))
        #expect(font.css.contains(#"font-family: "BowSerif" !important"#))

        let chapter = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).xhtml")
        try "<html><head></head><body><p>x</p></body></html>".write(to: chapter, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: chapter) }
        let preferences = BKUserPreferencesMock()
        preferences.fontChoice = font.storageKey
        let html = BKChapterHTMLBuilder.html(pathtofile: chapter.path, userPreferences: preferences,
                                             appearance: BKReaderAppearance(theme: .original, isDark: false), fonts: [font])
        #expect(html.contains("@font-face"))
        // Unknown host fonts (no longer offered) fall back to the book's own.
        let fallback = BKChapterHTMLBuilder.html(pathtofile: chapter.path, userPreferences: preferences,
                                                 appearance: BKReaderAppearance(theme: .original, isDark: false))
        #expect(!fallback.contains("@font-face"))
    }

    @Test func pageCurlCanBeTurnedOff() {
        var configuration = BKReaderConfiguration()
        #expect(configuration.allowsPageCurl)
        configuration.allowsPageCurl = false
        let settings = BKReaderSettingsViewModel(
            fontSize: .constant(3), textFont: .constant("original"), theme: .constant("original"),
            followsSystemAppearance: .constant(true), orientation: .constant("horizontal"),
            pageTransition: .constant("curl"), lineFocus: .constant(false), lineFocusStyle: .constant("guide"),
            textLayout: .constant(BKTextLayout()), rotationLock: .constant(false), themeColors: .constant([:]),
            systemIsDark: false, userPreferences: BKUserPreferencesMock(), configuration: configuration)
        #expect(!settings.configuration.allowsPageCurl)
    }
}

/// UI strings come from the package's own string catalog.
@Suite("Localization")
struct BKLocalizationTests {
    @Test func everyKeyInCodeIsInTheCatalog() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/BookKitRendering").standardizedFileURL
        let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let keys = Set(((catalog?["strings"] as? [String: Any]) ?? [:]).keys)

        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z_])L\("((?:[^"\\]|\\.)*)"\)"#)
        var missing: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                if !keys.contains(key) { missing.append("\(file.lastPathComponent): \(key)") }
            }
        }
        #expect(missing.isEmpty, "Add to Localizable.xcstrings: \(missing)")
    }

    @Test func stringsResolveFromThePackageBundle() {
        #expect(L("Contents") == "Contents")
        #expect(String(format: L("Back to Page %lld"), 12) == "Back to Page 12")
    }
}
