//
//  BKReaderViewBuilder.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import Foundation
import BookKitCore

public final class BKReaderViewBuilder {
    @MainActor
    public static func build(_ book: BKEpubBook,
                             spineIndex: Int,
                             initialCoords: String? = nil,
                             delegate: BKReaderCoordsProtocol?,
                             configuration: BKReaderConfiguration = BKReaderConfiguration()) -> BKReaderView {
        let viewModel = BKReaderViewModel(
            book: book,
            spineIndex: spineIndex,
            initialCoords: initialCoords,
            userPreferencesProtocol: configuration.defaults,
            delegate: delegate,
            configuration: configuration
        )
        BKFonts.registerAllFontsIfNeeded()
        let view = BKReaderView(viewModel: viewModel)
        return view
    }
}

final class BKReaderViewBuilderMock {
    @MainActor
    static func build(_ book: BKEpubBook,
                      spineIndex: Int) -> BKReaderView {
        let userPreferences: BKUserPreferencesProtocol = BKUserPreferencesMock()
        let viewModel = BKReaderViewModel(
            book: book,
            spineIndex: spineIndex,
            initialCoords: nil,
            userPreferencesProtocol: userPreferences,
            delegate: nil
        )
        let view = BKReaderView(viewModel: viewModel)
        return view
    }
}
