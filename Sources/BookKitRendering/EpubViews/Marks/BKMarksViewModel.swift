//
//  BKMarksViewModel.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 07/05/2026.
//

import Foundation
import BookKitCore

@MainActor
final class BKMarksViewModel: ObservableObject {

    /// Which highlights the list shows, like Books' Highlights filter.
    enum Filter: Hashable {
        case all
        /// Highlights with a note.
        case notes
        /// Highlights drawn in this style and color (`#RRGGBB`, uppercased).
        case look(BKAnnotationStyle, String)
    }

    enum Sort: Hashable, CaseIterable {
        /// In reading order.
        case position
        /// Most recently changed first.
        case recent

        var title: String {
            switch self {
            case .position: L("Page")
            case .recent: L("Date")
            }
        }
    }

    @Published var filter: Filter = .all
    @Published var sort: Sort = .position
    @Published private(set) var highlights: [BKHighlight] = []
    /// Mark types this list shows (highlights and notes, or bookmarks).
    let types: [BKHighlight.MarkType]

    private let highlightsProvider: () async -> [BKHighlight]
    private let onSelect: (BKHighlight) -> Void

    /// Whole-book page of a mark, once the book has been counted.
    let pageNumber: (BKHighlight) -> Int?
    /// Heads exported highlights ("Title by Author"); `nil` when this list doesn't export.
    let exportHeading: String?
    /// Names the colors in the filters.
    let highlightMenu: BKHighlightMenuConfiguration

    init(types: [BKHighlight.MarkType] = [.highlight, .note, .bookMark],
         highlightsProvider: @escaping () async -> [BKHighlight],
         pageNumber: @escaping (BKHighlight) -> Int? = { _ in nil },
         exportHeading: String? = nil,
         highlightMenu: BKHighlightMenuConfiguration = BKHighlightMenuConfiguration(),
         onSelect: @escaping (BKHighlight) -> Void) {
        self.pageNumber = pageNumber
        self.exportHeading = exportHeading
        self.highlightMenu = highlightMenu
        self.types = types
        self.highlightsProvider = highlightsProvider
        self.onSelect = onSelect
    }

    /// The kind of mark the list is about, for its icon and empty message.
    var primaryType: BKHighlight.MarkType {
        types.first ?? .highlight
    }

    /// Color and note filters apply to highlights, not bookmarks.
    var showsFilters: Bool {
        types.contains(.highlight) && !marks.isEmpty
    }

    /// The filters worth offering: All, Notes if any mark has one, and each style and color in use
    /// (in the order of the menu's palettes, then the order they first appear).
    var availableFilters: [Filter] {
        var filters: [Filter] = [.all]
        if marks.contains(where: \.hasNote) {
            filters.append(.notes)
        }
        var looks: [Filter] = []
        for mark in marks.sorted(by: isBefore) where !looks.contains(Self.look(of: mark)) {
            looks.append(Self.look(of: mark))
        }
        let order = highlightMenu.palettes.flatMap { palette in palette.colors.map { Filter.look(palette.style, $0.hex.uppercased()) } }
        return filters + looks.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }

    static func look(of mark: BKHighlight) -> Filter {
        .look(mark.annotationStyle, mark.color.uppercased())
    }

    /// The color's name from the palettes, else the style's name.
    func name(of style: BKAnnotationStyle, color: String) -> String {
        highlightMenu.colorName(color, style: style) ?? style.menuTitle
    }

    var filteredHighlights: [BKHighlight] {
        let shown = marks.filter { mark in
            switch filter {
            case .all: true
            case .notes: mark.hasNote
            case .look: Self.look(of: mark) == filter
            }
        }
        switch sort {
        case .position:
            return shown.sorted(by: isBefore)
        case .recent:
            return shown.sorted { $0.dateUpdated > $1.dateUpdated }
        }
    }

    /// Reading order: chapter, then whole-book page when both are known, then position in the chapter.
    private func isBefore(_ a: BKHighlight, _ b: BKHighlight) -> Bool {
        if a.spineIndex != b.spineIndex { return a.spineIndex < b.spineIndex }
        if let pageA = pageNumber(a), let pageB = pageNumber(b), pageA != pageB { return pageA < pageB }
        return Self.coordsKey(a.coords).lexicographicallyPrecedes(Self.coordsKey(b.coords))
    }

    /// A mark's start as numbers ("0000001>0000003>0000012,…" → [1, 3, 12]). Compared as strings,
    /// paths of different depths sort out of order.
    nonisolated static func coordsKey(_ coords: String) -> [Int] {
        let start = coords.split(separator: ",").first ?? ""
        return start.split(whereSeparator: { $0 == ">" || $0 == "|" }).compactMap { Int($0) }
    }

    /// Every mark of this list's types, before filtering.
    private var marks: [BKHighlight] {
        highlights.filter { types.contains($0.type) }
    }

    func loadIfNeeded() async {
        guard highlights.isEmpty else { return }
        highlights = await highlightsProvider()
        // A filter for a color that's no longer used would show nothing.
        if !availableFilters.contains(filter) {
            filter = .all
        }
    }

    // MARK: Export

    /// Whether Share is offered: on the highlights list, once there's something to share.
    var canExport: Bool {
        exportHeading != nil && !filteredHighlights.isEmpty
    }

    /// The highlights and notes listed (with the current filter and order), as text to share:
    /// the book, then each passage under its chapter and page, with its note.
    var exportText: String {
        var sections: [String] = []
        if let heading = exportHeading, !heading.isEmpty {
            sections.append(heading)
        }
        var lastChapter: String?
        for mark in filteredHighlights {
            var lines: [String] = []
            let chapter = mark.chapterTitle.isEmpty ? mark.chapterId : mark.chapterTitle
            if chapter != lastChapter {
                lines.append(chapter.uppercased())
                lastChapter = chapter
            }
            let page = pageNumber(mark).map { " " + String(format: L("(p. %lld)"), $0) } ?? ""
            lines.append("“\(mark.text.trimmingCharacters(in: .whitespacesAndNewlines))”\(page)")
            if mark.hasNote {
                lines.append(String(format: L("Note: %@"), mark.note.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            sections.append(lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    func didSelect(_ highlight: BKHighlight) {
        onSelect(highlight)
    }
}
