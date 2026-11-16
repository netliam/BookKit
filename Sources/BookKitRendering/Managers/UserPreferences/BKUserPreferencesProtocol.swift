//
//  BKUserPreferencesProtocol.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 3/11/25.
//

import Foundation
import BookKitCore

protocol BKUserPreferencesProtocol {
    func setValue(key: BKUserPreferences.CacheKey, type: Any)
    func getFontSize() -> BKFontSize
    func getFontFamily() -> BKFontFamily
    func getTheme() -> BKReaderTheme
    /// Whether themes switch to their dark palette when the system is in dark mode.
    func getFollowsSystemAppearance() -> Bool
    func getBookOrientation() -> BKBookrOrientation
    func getPageTransition() -> BKPageTransition
    func getLineFocus() -> Bool
    func getLineFocusStyle() -> BKLineFocusStyle
    /// Line spacing, margins and justification.
    func getTextLayout() -> BKTextLayout
    /// Whether the reader keeps the orientation it was in.
    func getRotationLock() -> Bool
    /// The stored font choice: a `BKFontFamily` raw value or a host font's `storageKey`.
    func getFontChoice() -> String
    /// Custom theme colors, keyed by `BKThemeColorStore.key`.
    func getThemeColors() -> [String: BKThemeColors]
    func setThemeColors(_ colors: [String: BKThemeColors])
    /// The style last chosen for a highlight, and the color last chosen in each style; Add Note
    /// and the menus start from them.
    func getLastAnnotationStyle() -> BKAnnotationStyle?
    func getLastHighlightColor(for style: BKAnnotationStyle) -> String?
    func setLastHighlight(style: BKAnnotationStyle, color: String)
}

extension UserDefaults: BKUserPreferencesProtocol {
    func setValue(key: BKUserPreferences.CacheKey, type: Any) {
        setValue(type, forKey: key.rawValue)
        synchronize()
    }

    func getFontSize() -> BKFontSize {
        guard let number = object(forKey: BKUserPreferences.CacheKey.fontSize.rawValue) as? NSNumber else {
            return .textSizeFour
        }
        switch number {
        case 0:
            return .textSizeOne
        case 1:
            return .textSizeTwo
        case 2:
            return .textSizeThree
        case 3:
            return .textSizeFour
        case 4:
            return .textSizeFive
        case 5:
            return .textSizeSix
        case 6:
            return .textSizeSeven
        case 7:
            return .textSizeEight
        default:
            return .textSizeFour
        }
    }

    func getFontFamily() -> BKFontFamily {
        string(forKey: BKUserPreferences.CacheKey.fontFamily.rawValue).flatMap(BKFontFamily.init(rawValue:)) ?? .original
    }

    func getTheme() -> BKReaderTheme {
        string(forKey: BKUserPreferences.CacheKey.theme.rawValue).flatMap(BKReaderTheme.init(rawValue:)) ?? .original
    }

    func getFollowsSystemAppearance() -> Bool {
        // Defaults to on, like Books.
        object(forKey: BKUserPreferences.CacheKey.followsSystemAppearance.rawValue) as? Bool ?? true
    }

    func getBookOrientation() -> BKBookrOrientation {
        guard let orientation = string(forKey: BKUserPreferences.CacheKey.bookOrientation.rawValue) else {
            return .horizontal
        }
        switch orientation {
        case "horizontal":
            return .horizontal
        case "vertical":
            return .vertical
        default:
            return .horizontal
        }
    }

    func getPageTransition() -> BKPageTransition {
        guard let transition = string(forKey: BKUserPreferences.CacheKey.pageTransition.rawValue) else {
            return .curl
        }
        return BKPageTransition(rawValue: transition) ?? .curl
    }

    func getLineFocus() -> Bool {
        bool(forKey: BKUserPreferences.CacheKey.lineFocus.rawValue)
    }

    func getLineFocusStyle() -> BKLineFocusStyle {
        string(forKey: BKUserPreferences.CacheKey.lineFocusStyle.rawValue).flatMap(BKLineFocusStyle.init(rawValue:)) ?? .guide
    }

    func getTextLayout() -> BKTextLayout {
        typealias Key = BKUserPreferences.CacheKey
        var layout = BKTextLayout()
        if let spacing = string(forKey: Key.lineSpacing.rawValue).flatMap(BKLineSpacing.init(rawValue:)) {
            layout.lineSpacing = spacing
        }
        if let margins = string(forKey: Key.pageMargins.rawValue).flatMap(BKPageMargins.init(rawValue:)) {
            layout.margins = margins
        }
        // Justified unless turned off.
        layout.justified = object(forKey: Key.justifyText.rawValue) as? Bool ?? true
        layout.allowsSpreads = object(forKey: Key.allowSpreads.rawValue) as? Bool ?? true
        let steps = BKTextLayout.spacingSteps
        layout.characterSpacing = min(max(integer(forKey: Key.characterSpacing.rawValue), steps.lowerBound), steps.upperBound)
        layout.wordSpacing = min(max(integer(forKey: Key.wordSpacing.rawValue), steps.lowerBound), steps.upperBound)
        return layout
    }

    func getRotationLock() -> Bool {
        bool(forKey: BKUserPreferences.CacheKey.rotationLock.rawValue)
    }

    func getFontChoice() -> String {
        string(forKey: BKUserPreferences.CacheKey.fontFamily.rawValue) ?? BKFontFamily.original.rawValue
    }

    func getThemeColors() -> [String: BKThemeColors] {
        guard let data = data(forKey: BKUserPreferences.CacheKey.themeColors.rawValue) else { return [:] }
        return (try? JSONDecoder().decode([String: BKThemeColors].self, from: data)) ?? [:]
    }

    func setThemeColors(_ colors: [String: BKThemeColors]) {
        set(try? JSONEncoder().encode(colors), forKey: BKUserPreferences.CacheKey.themeColors.rawValue)
    }

    /// Before styles and colors were separate, one `BKHighlightStyle` name was kept.
    private var legacyHighlightStyle: BKHighlightStyle? {
        string(forKey: BKUserPreferences.CacheKey.lastHighlightStyle.rawValue).flatMap(BKHighlightStyle.init(rawValue:))
    }

    func getLastAnnotationStyle() -> BKAnnotationStyle? {
        string(forKey: BKUserPreferences.CacheKey.lastAnnotationStyle.rawValue).flatMap(BKAnnotationStyle.init(rawValue:))
            ?? legacyHighlightStyle?.annotationStyle
    }

    func getLastHighlightColor(for style: BKAnnotationStyle) -> String? {
        let colors = dictionary(forKey: BKUserPreferences.CacheKey.lastHighlightColors.rawValue) as? [String: String]
        if let color = colors?[style.rawValue] { return color }
        return legacyHighlightStyle.flatMap { $0.annotationStyle == style ? $0.color : nil }
    }

    func setLastHighlight(style: BKAnnotationStyle, color: String) {
        var colors = dictionary(forKey: BKUserPreferences.CacheKey.lastHighlightColors.rawValue) as? [String: String] ?? [:]
        colors[style.rawValue] = color
        set(colors, forKey: BKUserPreferences.CacheKey.lastHighlightColors.rawValue)
        set(style.rawValue, forKey: BKUserPreferences.CacheKey.lastAnnotationStyle.rawValue)
    }
}
