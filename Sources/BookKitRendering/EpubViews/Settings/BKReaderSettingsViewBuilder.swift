//
//  BKReaderSettingsViewBuilder.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

final class BKReaderSettingsViewBuilder {
    @MainActor
    func build(fontSize: Binding<CGFloat>,
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
               windowScene: UIWindowScene? = nil) -> BKReaderSettingsView {
        let viewModel = BKReaderSettingsViewModel(fontSize: fontSize,
                                                  textFont: textFont,
                                                  theme: theme,
                                                  followsSystemAppearance: followsSystemAppearance,
                                                  orientation: orientation,
                                                  pageTransition: pageTransition,
                                                  lineFocus: lineFocus,
                                                  lineFocusStyle: lineFocusStyle,
                                                  textLayout: textLayout,
                                                  rotationLock: rotationLock,
                                                  themeColors: themeColors,
                                                  systemIsDark: systemIsDark,
                                                  userPreferences: userPreferences,
                                                  configuration: configuration,
                                                  windowScene: windowScene)
        return BKReaderSettingsView(viewModel: viewModel)
    }
}
