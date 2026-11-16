//
//  BKReaderSettingsViewModel.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

@MainActor
final class BKReaderSettingsViewModel: ObservableObject {

    @Binding var fontSize: CGFloat
    @Binding var textFont: String
    @Binding var theme: String
    @Binding var followsSystemAppearance: Bool
    @Binding var orientation: String
    @Binding var pageTransition: String
    @Binding var lineFocus: Bool
    @Binding var lineFocusStyle: String
    @Binding var textLayout: BKTextLayout
    @Binding var rotationLock: Bool
    @Binding var themeColors: [String: BKThemeColors]

    /// Whether the system is in dark mode, to preview the theme tiles in the palette that will be used.
    let systemIsDark: Bool
    let configuration: BKReaderConfiguration
    /// The reader's window, for brightness and whether rotation lock applies.
    weak var windowScene: UIWindowScene?

    var showsRotationLock: Bool {
        configuration.showsRotationLock && BKReaderOrientationLock.isAvailable(in: windowScene)
    }
    let userPreferences: BKUserPreferencesProtocol

    private let fontSizeRange: ClosedRange<CGFloat> = 0...7

    init(fontSize: Binding<CGFloat>,
         textFont: Binding<String>,
         theme: Binding<String>,
         followsSystemAppearance: Binding<Bool>,
         orientation: Binding<String>,
         pageTransition: Binding<String>,
         lineFocus: Binding<Bool>,
         lineFocusStyle: Binding<String>,
         textLayout: Binding<BKTextLayout>,
         rotationLock: Binding<Bool>,
         themeColors: Binding<[String: BKThemeColors]>,
         systemIsDark: Bool,
         userPreferences: BKUserPreferencesProtocol,
         configuration: BKReaderConfiguration = BKReaderConfiguration(),
         windowScene: UIWindowScene? = nil) {
        self.configuration = configuration
        self.windowScene = windowScene
        self._fontSize = fontSize
        self._textFont = textFont
        self._theme = theme
        self._followsSystemAppearance = followsSystemAppearance
        self._orientation = orientation
        self._pageTransition = pageTransition
        self._lineFocus = lineFocus
        self._lineFocusStyle = lineFocusStyle
        self._textLayout = textLayout
        self._rotationLock = rotationLock
        self._themeColors = themeColors
        self.systemIsDark = systemIsDark
        self.userPreferences = userPreferences
    }

    // MARK: Text size

    var canDecreaseFontSize: Bool { fontSize > fontSizeRange.lowerBound }
    var canIncreaseFontSize: Bool { fontSize < fontSizeRange.upperBound }

    func changeFontSize(by step: CGFloat) {
        let newValue = min(max(fontSize + step, fontSizeRange.lowerBound), fontSizeRange.upperBound)
        guard newValue != fontSize else { return }
        userPreferences.setValue(key: .fontSize, type: newValue)
        fontSize = newValue
    }

    // MARK: Themes

    var selectedTheme: BKReaderTheme {
        BKReaderTheme(rawValue: theme) ?? .original
    }

    /// Tiles preview the palette the reader would actually use right now.
    func previewAppearance(for theme: BKReaderTheme) -> BKReaderAppearance {
        let isDark = followsSystemAppearance && systemIsDark
        return BKReaderAppearance(theme: theme, isDark: isDark,
                                  custom: themeColors[BKThemeColorStore.key(theme, isDark: isDark)])
    }

    func select(_ theme: BKReaderTheme) {
        userPreferences.setValue(key: .theme, type: theme.rawValue)
        self.theme = theme.rawValue
    }

    func toggleFollowsSystemAppearance() {
        let newValue = !followsSystemAppearance
        userPreferences.setValue(key: .followsSystemAppearance, type: newValue)
        followsSystemAppearance = newValue
    }

    // MARK: Layout

    var isScrolling: Bool {
        orientation == BKBookrOrientation.vertical.rawValue
    }

    func setScrolling(_ scrolling: Bool) {
        let value = (scrolling ? BKBookrOrientation.vertical : .horizontal).rawValue
        userPreferences.setValue(key: .bookOrientation, type: value)
        orientation = value
    }

    var selectedTransition: BKPageTransition {
        BKPageTransition(rawValue: pageTransition) ?? .curl
    }

    func select(_ transition: BKPageTransition) {
        userPreferences.setValue(key: .pageTransition, type: transition.rawValue)
        pageTransition = transition.rawValue
    }

    func select(_ font: BKFontFamily) {
        userPreferences.setValue(key: .fontFamily, type: font.rawValue)
        textFont = font.rawValue
    }

    func select(_ font: BKReaderFont) {
        userPreferences.setValue(key: .fontFamily, type: font.storageKey)
        textFont = font.storageKey
    }

    func isSelected(_ font: BKFontFamily) -> Bool {
        // Older builds stored the display name rather than the raw value.
        textFont == font.rawValue || textFont == font.name
    }

    func setLineFocus(_ isOn: Bool) {
        userPreferences.setValue(key: .lineFocus, type: isOn)
        lineFocus = isOn
    }

    var selectedLineFocusStyle: BKLineFocusStyle {
        BKLineFocusStyle(rawValue: lineFocusStyle) ?? .guide
    }

    // MARK: Theme colors

    /// The palette the reader uses now (the selected theme, light or dark), which Customize edits.
    var currentAppearance: BKReaderAppearance {
        previewAppearance(for: selectedTheme)
    }

    var currentPaletteName: String {
        let isDark = followsSystemAppearance && systemIsDark
        return isDark ? String(format: L("%@ (Dark)"), selectedTheme.name) : selectedTheme.name
    }

    func setThemeColors(background: UIColor? = nil, text: UIColor? = nil) {
        let current = currentAppearance
        var colors = BKThemeColors(background: current.background, text: current.text)
        if let background { colors.background = BKReaderAppearance.hex(background) }
        if let text { colors.text = BKReaderAppearance.hex(text) }
        let key = BKThemeColorStore.key(selectedTheme, isDark: current.isDark)
        guard themeColors[key] != colors else { return }
        themeColors[key] = colors
        userPreferences.setThemeColors(themeColors)
    }

    func resetThemeColors() {
        let key = BKThemeColorStore.key(selectedTheme, isDark: currentAppearance.isDark)
        themeColors[key] = nil
        userPreferences.setThemeColors(themeColors)
    }

    func setRotationLock(_ locked: Bool) {
        userPreferences.setValue(key: .rotationLock, type: locked)
        rotationLock = locked
    }

    // MARK: Text layout

    func select(_ spacing: BKLineSpacing) {
        userPreferences.setValue(key: .lineSpacing, type: spacing.rawValue)
        textLayout.lineSpacing = spacing
    }

    func select(_ margins: BKPageMargins) {
        userPreferences.setValue(key: .pageMargins, type: margins.rawValue)
        textLayout.margins = margins
    }

    func setCharacterSpacing(_ step: Int) {
        guard step != textLayout.characterSpacing else { return }
        userPreferences.setValue(key: .characterSpacing, type: step)
        textLayout.characterSpacing = step
    }

    func setWordSpacing(_ step: Int) {
        guard step != textLayout.wordSpacing else { return }
        userPreferences.setValue(key: .wordSpacing, type: step)
        textLayout.wordSpacing = step
    }

    func setAllowsSpreads(_ allowed: Bool) {
        userPreferences.setValue(key: .allowSpreads, type: allowed)
        textLayout.allowsSpreads = allowed
    }

    func setJustified(_ justified: Bool) {
        userPreferences.setValue(key: .justifyText, type: justified)
        textLayout.justified = justified
    }

    func select(_ style: BKLineFocusStyle) {
        userPreferences.setValue(key: .lineFocusStyle, type: style.rawValue)
        lineFocusStyle = style.rawValue
    }
}
