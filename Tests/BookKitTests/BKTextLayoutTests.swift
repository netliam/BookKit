//
//  BKTextLayoutTests.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import SwiftUI
import BookKitCore
import BookKitParser
@testable import BookKitRendering

/// Line spacing, margins and justification.
@Suite("Text layout settings")
struct BKTextLayoutTests {

    @Test func defaultsKeepTheBooksLayout() {
        let layout = BKTextLayout()
        #expect(layout.lineSpacing == .original)
        #expect(layout.margins == .normal)
        #expect(layout.justified)
        // Nothing to override, and the margins are the reader's long-standing inset.
        #expect(layout.css.isEmpty)
        #expect(layout.margins.inset == BKReaderChrome.horizontalInset)
    }

    @Test func cssSetsLineHeightAndAlignment() {
        let layout = BKTextLayout(lineSpacing: .relaxed, margins: .wide, justified: false)
        #expect(layout.css.contains("line-height: 1.75 !important"))
        #expect(layout.css.contains("text-align: start !important"))
        #expect(BKPageMargins.allCases.map(\.inset) == BKPageMargins.allCases.map(\.inset).sorted())
    }

    @Test func storedInUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "BKTextLayoutTests-\(UUID().uuidString)"))
        #expect(defaults.getTextLayout() == BKTextLayout())
        defaults.setValue(key: .lineSpacing, type: BKLineSpacing.loose.rawValue)
        defaults.setValue(key: .pageMargins, type: BKPageMargins.narrow.rawValue)
        defaults.setValue(key: .justifyText, type: false)
        #expect(defaults.getTextLayout() == BKTextLayout(lineSpacing: .loose, margins: .narrow, justified: false))
    }

    @Test @MainActor func changingItLaysTheBookOutAgain() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let reader = BKReaderViewModel(book: try BKEpubParser.parse(from: url),
                                       spineIndex: 0,
                                       userPreferencesProtocol: BKUserPreferencesMock(),
                                       delegate: nil)
        let paged = reader.pagedConfigId
        let scrolling = reader.readerConfigId(for: 0)
        reader.textLayout.lineSpacing = .loose
        #expect(reader.pagedConfigId != paged)
        #expect(reader.readerConfigId(for: 0) != scrolling)
    }
}

/// Rotation lock: the setting and the orientation it locks to.
@MainActor
@Suite("Rotation lock")
struct BKRotationLockTests {
    @Test func locksToTheOrientationOnScreen() {
        #expect(BKReaderOrientationLock.mask(for: .portrait) == .portrait)
        #expect(BKReaderOrientationLock.mask(for: .landscapeLeft) == .landscapeLeft)
        #expect(BKReaderOrientationLock.mask(for: .landscapeRight) == .landscapeRight)
        #expect(BKReaderOrientationLock.mask(for: .unknown) == .portrait)
    }

    @Test func settingIsStoredAndUnlockedByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "BKRotationLockTests-\(UUID().uuidString)"))
        #expect(defaults.getRotationLock() == false)
        defaults.setValue(key: .rotationLock, type: true)
        #expect(defaults.getRotationLock())
    }

    @Test func closingTheReaderUnlocks() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let preferences = BKUserPreferencesMock()
        preferences.rotationLock = true
        let reader = BKReaderViewModel(book: try BKEpubParser.parse(from: url), spineIndex: 0,
                                       userPreferencesProtocol: preferences, delegate: nil)
        reader.readerDidAppear()
        reader.readerDidDisappear()
        #expect(BKReaderOrientationLock.supportedOrientations(for: nil) == .all)
    }
}

/// More fonts, and character and word spacing.
@Suite("Fonts and spacing")
struct BKFontsAndSpacingTests {
    @Test func everyFontHasAStylesheetRule() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/BookKitRendering/Resources/Style.css")
        let css = try String(contentsOf: url, encoding: .utf8)
        for font in BKFontFamily.allCases where font != .original {
            #expect(css.contains(".\(font.rawValue), .\(font.rawValue) p"), "Missing a rule for \(font.rawValue)")
        }
        // System fonts use the same stack in Swift and CSS.
        for font in BKFontFamily.allCases {
            if let stack = font.systemFontStack {
                #expect(css.contains("font-family: \(stack) !important"), "\(font.rawValue)")
            }
        }
    }

    @Test func fontsAndSpacingAreStored() throws {
        let defaults = try #require(UserDefaults(suiteName: "BKFontsAndSpacingTests-\(UUID().uuidString)"))
        defaults.setValue(key: .fontFamily, type: BKFontFamily.iowan.rawValue)
        #expect(defaults.getFontFamily() == .iowan)
        defaults.setValue(key: .fontFamily, type: "no-such-font")
        #expect(defaults.getFontFamily() == .original)

        defaults.setValue(key: .characterSpacing, type: 2)
        defaults.setValue(key: .wordSpacing, type: 9)
        let layout = defaults.getTextLayout()
        #expect(layout.characterSpacing == 2)
        #expect(layout.wordSpacing == BKTextLayout.spacingSteps.upperBound, "out-of-range values are clamped")
    }

    @Test func spacingAddsCSSAndLaysOutAgain() {
        var layout = BKTextLayout()
        let id = layout.id
        layout.characterSpacing = 3
        layout.wordSpacing = 1
        #expect(layout.css.contains("letter-spacing: 0.06em !important"))
        #expect(layout.css.contains("word-spacing: 0.1em !important"))
        #expect(layout.id != id)
    }
}

/// Custom theme colors (Customize → Theme Colors).
@MainActor
@Suite("Custom theme colors", .serialized)
struct BKThemeColorTests {

    @Test func appearanceUsesCustomColorsForItsPaletteOnly() throws {
        let defaults = try #require(UserDefaults(suiteName: "BKThemeColorTests-\(UUID().uuidString)"))
        #expect(defaults.getThemeColors().isEmpty)
        defaults.setThemeColors([BKThemeColorStore.key(.paper, isDark: false): BKThemeColors(background: 0x102030, text: 0xF0E0D0)])
        let stored = defaults.getThemeColors()
        func appearance(_ theme: BKReaderTheme, dark: Bool) -> BKReaderAppearance {
            BKReaderAppearance(theme: theme, isDark: dark, custom: stored[BKThemeColorStore.key(theme, isDark: dark)])
        }

        let custom = appearance(.paper, dark: false)
        #expect(custom.cssTextColor == "#F0E0D0")
        #expect(BKReaderAppearance.hex(custom.uiBackgroundColor) == 0x102030)
        #expect(custom.hasCustomColors)
        #expect(custom.hasDarkBackground, "a dark custom background in a light palette")
        #expect(custom != BKReaderAppearance(theme: .paper, isDark: false))

        // Paper's dark palette and other themes are unchanged.
        #expect(!appearance(.paper, dark: true).hasCustomColors)
        #expect(!appearance(.calm, dark: false).hasCustomColors)
        #expect(!BKReaderAppearance(theme: .original, isDark: false).hasDarkBackground)
    }

    @Test func customizeSetsAndResetsTheCurrentPalette() {
        var colors: [String: BKThemeColors] = [:]
        var theme = BKReaderTheme.calm.rawValue
        let preferences = BKUserPreferencesMock()
        let settings = BKReaderSettingsViewModel(
            fontSize: .constant(3), textFont: .constant("original"),
            theme: Binding(get: { theme }, set: { theme = $0 }),
            followsSystemAppearance: .constant(true), orientation: .constant("horizontal"),
            pageTransition: .constant("curl"), lineFocus: .constant(false), lineFocusStyle: .constant("guide"),
            textLayout: .constant(BKTextLayout()), rotationLock: .constant(false),
            themeColors: Binding(get: { colors }, set: { colors = $0 }),
            systemIsDark: false, userPreferences: preferences)

        settings.setThemeColors(background: UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        let key = BKThemeColorStore.key(.calm, isDark: false)
        #expect(colors[key]?.background == 0xFF0000)
        #expect(colors[key]?.text == BKReaderTheme.calm.palette(isDark: false).text, "text keeps the theme's")
        #expect(preferences.themeColors[key] == colors[key], "saved")
        #expect(settings.currentAppearance.hasCustomColors)

        settings.resetThemeColors()
        #expect(colors[key] == nil)
        #expect(preferences.themeColors.isEmpty)
    }
}
