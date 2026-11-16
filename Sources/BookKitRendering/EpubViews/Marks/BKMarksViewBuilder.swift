//
//  BKMarksViewBuilder.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 07/05/2026.
//

import SwiftUI
import BookKitCore

@MainActor
final class BKMarksViewBuilder {
    func build(types: [BKHighlight.MarkType] = [.highlight, .note, .bookMark],
               highlightsProvider: @escaping () async -> [BKHighlight],
               pageNumber: @escaping (BKHighlight) -> Int? = { _ in nil },
               exportHeading: String? = nil,
               highlightMenu: BKHighlightMenuConfiguration = BKHighlightMenuConfiguration(),
               onSelect: @escaping (BKHighlight) -> Void) -> BKMarksView {
        let viewModel = BKMarksViewModel(
            types: types,
            highlightsProvider: highlightsProvider,
            pageNumber: pageNumber,
            exportHeading: exportHeading,
            highlightMenu: highlightMenu,
            onSelect: onSelect
        )
        return BKMarksView(viewModel: viewModel)
    }
}
