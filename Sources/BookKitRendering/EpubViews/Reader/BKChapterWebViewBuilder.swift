//
//  BKChapterWebViewBuilder.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 2/11/25.
//

import Foundation
import BookKitCore

final class BKChapterWebViewBuilder {
    @MainActor
    func build(chapterURL: URL,
               readAccessURL: URL,
               spineIndex: Int,
               userPreferences: BKUserPreferencesProtocol,
               appearance: BKReaderAppearance,
               readerContext: any BKChapterReaderContextProtocol,
               onAction: @escaping (BKChapterViewAction) -> Void) -> BKChapterWebView {
        let viewModel = BKChapterWebViewModel(
            chapterURL: chapterURL,
            readAccessURL: readAccessURL,
            spineIndex: spineIndex,
            userPreferences: userPreferences,
            appearance: appearance,
            readerContext: readerContext,
            onAction: onAction
        )
        let view = BKChapterWebView(viewModel: viewModel)
        return view
    }
}
