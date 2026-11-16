//
//  BKUserPreferencesMock.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 27/10/25.
//

import Foundation
import BookKitCore

final class BKUserPreferencesMock: BKUserPreferencesProtocol {
    var lineFocus = false
    var lineFocusStyle: BKLineFocusStyle = .guide
    var textLayout = BKTextLayout()
    var rotationLock = false
    var fontChoice = BKFontFamily.original.rawValue
    var themeColors: [String: BKThemeColors] = [:]
    var lastAnnotationStyle: BKAnnotationStyle?
    var lastHighlightColors: [BKAnnotationStyle: String] = [:]

    func setValue(key: BKUserPreferences.CacheKey, type: Any) {}
    func getFontSize() -> BKFontSize {
        .textSizeFour
    }

    func getFontFamily() -> BKFontFamily {
        .original
    }

    func getTheme() -> BKReaderTheme {
        .original
    }

    func getFollowsSystemAppearance() -> Bool {
        true
    }

    func getBookOrientation() -> BKBookrOrientation {
        .horizontal
    }

    func getPageTransition() -> BKPageTransition {
        .curl
    }

    func getLineFocus() -> Bool {
        lineFocus
    }

    func getLineFocusStyle() -> BKLineFocusStyle {
        lineFocusStyle
    }

    func getTextLayout() -> BKTextLayout {
        textLayout
    }

    func getRotationLock() -> Bool {
        rotationLock
    }

    func getFontChoice() -> String { fontChoice }
    func getThemeColors() -> [String: BKThemeColors] { themeColors }
    func setThemeColors(_ colors: [String: BKThemeColors]) { themeColors = colors }
    func getLastAnnotationStyle() -> BKAnnotationStyle? { lastAnnotationStyle }
    func getLastHighlightColor(for style: BKAnnotationStyle) -> String? { lastHighlightColors[style] }
    func setLastHighlight(style: BKAnnotationStyle, color: String) {
        lastAnnotationStyle = style
        lastHighlightColors[style] = color
    }
}
