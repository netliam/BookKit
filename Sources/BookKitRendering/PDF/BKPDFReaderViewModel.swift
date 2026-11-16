//
//  BKPDFReaderViewModel.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import PDFKit
import SwiftUI
import BookKitCore

/// A search match in a PDF.
struct BKPDFSearchResult: Identifiable {
    let id: Int
    let pageIndex: Int
    /// The match with some text around it.
    let snippet: String
    let selection: PDFSelection
}

/// State of the PDF reader: page, marks, contents and search. Highlights and bookmarks are
/// `BKHighlight`s with `BKPDFLocation` coords, saved through the same stores as EPUB marks.
@MainActor
final class BKPDFReaderViewModel: NSObject, ObservableObject {

    let document: PDFDocument
    let fileURL: URL
    let bookId: String
    let title: String
    let menuConfiguration: BKHighlightMenuConfiguration
    private let highlightStore: BKHighlightStoreProtocol?
    private let positionStore: BKReadingPositionStoreProtocol?

    @Published private(set) var pageIndex = 0
    @Published var isChromeVisible = false
    @Published var showContents = false
    @Published var showSearch = false
    @Published var showShare = false
    /// Highlights and bookmarks of this book.
    @Published private(set) var marks: [BKHighlight] = []

    // Search
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [BKPDFSearchResult] = []
    @Published private(set) var isSearching = false

    /// Shows highlights and moves pages; set by the view.
    weak var pdfView: BKPDFView?
    /// Drawn annotations per highlight uuid.
    private var annotations: [String: PDFAnnotation] = [:]
    private var positionTask: Task<Void, Never>?
    private var pendingMatches: [PDFSelection] = []
    /// Cancelled searches whose end hasn't been reported yet; their late callbacks are ignored.
    private var cancelledSearches = 0

    init(document: PDFDocument,
         fileURL: URL,
         bookId: String,
         highlightStore: BKHighlightStoreProtocol?,
         positionStore: BKReadingPositionStoreProtocol?,
         menuConfiguration: BKHighlightMenuConfiguration) {
        self.document = document
        self.fileURL = fileURL
        self.bookId = bookId
        self.highlightStore = highlightStore
        self.positionStore = positionStore
        self.menuConfiguration = menuConfiguration
        let attributeTitle = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = attributeTitle.flatMap { $0.isEmpty ? nil : $0 } ?? fileURL.deletingPathExtension().lastPathComponent
        super.init()
        document.delegate = self
    }

    var pageCount: Int { document.pageCount }

    var pageText: String {
        String(format: L("%lld of %lld"), pageIndex + 1, max(pageCount, 1))
    }

    // MARK: - Loading

    /// Loads saved marks, draws the highlights and opens the saved page.
    func load() async {
        marks = await highlightStore?.highlights(bookId: bookId) ?? []
        for mark in marks where mark.type != .bookMark {
            draw(mark)
        }
        if let position = await positionStore?.position(bookId: bookId),
           let location = BKPDFLocation(coords: position.coords) {
            go(toPage: location.pageIndex)
        }
    }

    /// The view moved to `page`: remember it as the reading position (after the reader settles).
    func pageDidChange(to page: Int) {
        guard page != pageIndex else { return }
        pageIndex = page
        isChromeVisible = false
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.positionStore?.save(position: BKReadingPosition(bookId: self.bookId,
                                                                       spineIndex: page,
                                                                       coords: BKPDFLocation(pageIndex: page).coords,
                                                                       chapterId: Self.chapterId(page)))
        }
    }

    func go(toPage page: Int) {
        guard let pdfPage = document.page(at: min(max(0, page), pageCount - 1)) else { return }
        pdfView?.go(to: pdfPage)
        pageDidChange(to: document.index(for: pdfPage))
    }

    static func chapterId(_ page: Int) -> String { "page-\(page + 1)" }

    // MARK: - Contents

    /// The outline, flattened, pointing at pages.
    var contentsEntries: [BKContentsEntry] {
        var entries: [BKContentsEntry] = []
        func visit(_ item: PDFOutline, depth: Int) {
            for index in 0..<item.numberOfChildren {
                guard let child = item.child(at: index) else { continue }
                let page = child.destination?.page.map { document.index(for: $0) }
                entries.append(BKContentsEntry(id: entries.count, label: child.label ?? "", depth: depth,
                                               spineIndex: page, fragment: nil))
                visit(child, depth: depth + 1)
            }
        }
        if let root = document.outlineRoot { visit(root, depth: 0) }
        return entries
    }

    /// Title of the outline section a page belongs to, for marks lists.
    func sectionTitle(forPage page: Int) -> String {
        contentsEntries.last { ($0.spineIndex ?? .max) <= page }?.label ?? title
    }

    // MARK: - Bookmarks

    var isCurrentPageBookmarked: Bool {
        marks.contains { $0.type == .bookMark && $0.spineIndex == pageIndex }
    }

    func toggleBookmark() {
        if let existing = marks.filter({ $0.type == .bookMark && $0.spineIndex == pageIndex }).first {
            marks.removeAll { $0.uuid == existing.uuid }
            Task { await highlightStore?.delete(uuid: existing.uuid) }
            return
        }
        let page = pageIndex
        // The start of the page, on one line.
        let text = (document.page(at: page)?.string ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .prefix(120)
        let bookmark = BKHighlight(uuid: UUID().uuidString, bookId: bookId, chapterId: Self.chapterId(page),
                                   spineIndex: page, type: .bookMark, text: String(text),
                                   coords: BKPDFLocation(pageIndex: page).coords,
                                   chapterTitle: sectionTitle(forPage: page))
        marks.append(bookmark)
        Task { await highlightStore?.save(bookmark) }
    }

    // MARK: - Highlights

    /// Highlights `selection` (one highlight per page it covers) and saves it.
    func highlight(_ selection: PDFSelection, style: BKAnnotationStyle, color: String) {
        var linesByPage: [Int: [PDFSelection]] = [:]
        for line in selection.selectionsByLine() {
            guard let page = line.pages.first else { continue }
            linesByPage[document.index(for: page), default: []].append(line)
        }
        for (page, lines) in linesByPage.sorted(by: { $0.key < $1.key }) {
            guard let pdfPage = document.page(at: page) else { continue }
            let rects = lines.map { $0.bounds(for: pdfPage) }.filter { !$0.isEmpty }
            let text = lines.compactMap(\.string).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rects.isEmpty, !text.isEmpty else { continue }
            let highlight = BKHighlight(uuid: UUID().uuidString, bookId: bookId, chapterId: Self.chapterId(page),
                                        spineIndex: page, type: .highlight, text: text,
                                        coords: BKPDFLocation(pageIndex: page, rects: rects).coords,
                                        chapterTitle: sectionTitle(forPage: page),
                                        annotationStyle: style, color: color)
            marks.append(highlight)
            draw(highlight)
            Task { await highlightStore?.save(highlight) }
        }
        pdfView?.clearSelection()
    }

    func delete(_ highlight: BKHighlight) {
        if let annotation = annotations.removeValue(forKey: highlight.uuid) {
            annotation.page?.removeAnnotation(annotation)
        }
        marks.removeAll { $0.uuid == highlight.uuid }
        Task { await highlightStore?.delete(uuid: highlight.uuid) }
    }

    func recolor(_ highlight: BKHighlight, style: BKAnnotationStyle, color: String) {
        var updated = highlight
        updated.annotationStyle = style
        updated.color = color
        updated.dateUpdated = Date().timeIntervalSince1970
        if let index = marks.firstIndex(where: { $0.uuid == highlight.uuid }) { marks[index] = updated }
        draw(updated)
        Task { await highlightStore?.save(updated) }
    }

    /// The saved highlight drawn at `point` (page space) on `page`, if any.
    func highlight(at point: CGPoint, on page: PDFPage) -> BKHighlight? {
        let index = document.index(for: page)
        return marks.last { mark in
            guard mark.type != .bookMark, mark.spineIndex == index,
                  let location = BKPDFLocation(coords: mark.coords) else { return false }
            return location.rects.contains { $0.insetBy(dx: -2, dy: -2).contains(point) }
        }
    }

    /// Adds (or replaces) the annotation drawing `highlight`. The PDF file itself isn't changed.
    private func draw(_ highlight: BKHighlight) {
        if let old = annotations.removeValue(forKey: highlight.uuid) {
            old.page?.removeAnnotation(old)
        }
        guard let location = BKPDFLocation(coords: highlight.coords), !location.rects.isEmpty,
              let page = document.page(at: location.pageIndex) else { return }
        let annotation = Self.annotation(for: highlight, location: location)
        page.addAnnotation(annotation)
        annotations[highlight.uuid] = annotation
    }

    static func annotation(for highlight: BKHighlight, location: BKPDFLocation) -> PDFAnnotation {
        let bounds = location.bounds
        let subtype: PDFAnnotationSubtype = switch highlight.annotationStyle {
        case .highlight: .highlight
        case .underline, .squiggly: .underline
        case .strikethrough: .strikeOut
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
        // One quadrilateral per line, relative to the annotation's origin.
        annotation.quadrilateralPoints = location.rects.flatMap { rect -> [NSValue] in
            let r = rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
                    CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)].map { NSValue(cgPoint: $0) }
        }
        let color = UIColor(hex: highlight.color) ?? .systemYellow
        // PDFKit blends highlight annotations with the page, so the text stays readable at full color.
        annotation.color = color
        return annotation
    }

    // MARK: - Navigation to marks

    func navigate(to mark: BKHighlight) {
        go(toPage: mark.spineIndex)
        showContents = false
    }

    func navigate(to entry: BKContentsEntry) {
        if let page = entry.spineIndex { go(toPage: page) }
        showContents = false
    }

    // MARK: - Search

    func search(_ query: String) {
        if isSearching {
            document.cancelFindString()
            cancelledSearches += 1
        }
        searchQuery = query
        searchResults = []
        pendingMatches = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        document.beginFindString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    func select(_ result: BKPDFSearchResult) {
        showSearch = false
        guard let pdfView else { return }
        pdfView.go(to: result.selection)
        pdfView.highlightedSelections = [result.selection]
        if let page = result.selection.pages.first {
            pageDidChange(to: document.index(for: page))
        }
    }

    /// Opens search for `text` (the selection menu's Search).
    func searchBook(for text: String) {
        search(text)
        showSearch = true
    }

    private func appendResults(_ matches: [PDFSelection]) {
        for match in matches {
            guard let page = match.pages.first, searchResults.count < 500 else { continue }
            let context = match.copy() as? PDFSelection ?? match
            context.extend(atStart: 40)
            context.extend(atEnd: 60)
            let snippet = Self.snippet(context.string ?? match.string ?? "", match: match.string ?? "")
            searchResults.append(BKPDFSearchResult(id: searchResults.count, pageIndex: document.index(for: page),
                                                   snippet: snippet, selection: match))
        }
    }

    /// `text` on one line, without the partial words its ends were cut through.
    static func snippet(_ text: String, match: String) -> String {
        var words = text.replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard words.count > 2 else { return words.joined(separator: " ") }
        let lowerMatch = match.lowercased()
        if !words[0].lowercased().contains(lowerMatch) { words[0] = "…" }
        if !words[words.count - 1].lowercased().contains(lowerMatch) { words[words.count - 1] = "…" }
        return words.joined(separator: " ")
            .replacingOccurrences(of: "… ", with: "…", options: .anchored)
            .replacingOccurrences(of: " …", with: "…", options: [.anchored, .backwards])
    }

    // MARK: - Share

    /// The selected text, or the PDF file under the book's title.
    var shareItems: [Any] {
        if let text = pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return [text]
        }
        let named = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookKitShare", isDirectory: true)
            .appendingPathComponent(title.replacingOccurrences(of: "/", with: "-") + ".pdf")
        try? FileManager.default.createDirectory(at: named.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: named)
        if (try? FileManager.default.linkItem(at: fileURL, to: named)) != nil
            || (try? FileManager.default.copyItem(at: fileURL, to: named)) != nil {
            return [named]
        }
        return [fileURL]
    }
}

// MARK: - PDFDocumentDelegate (search)

extension BKPDFReaderViewModel: PDFDocumentDelegate {
    // PDFKit may report matches from its search thread. The main queue keeps them in order, so the
    // end of the search is handled after the last match.
    nonisolated func didMatchString(_ instance: PDFSelection) {
        nonisolated(unsafe) let match = instance
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.received(match) }
        }
    }

    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.searchDidEnd() }
        }
    }

    private func received(_ match: PDFSelection) {
        guard cancelledSearches == 0 else { return }
        pendingMatches.append(match)
        // Publish in batches so long searches don't redraw the list for every match.
        if pendingMatches.count >= 20 {
            appendResults(pendingMatches)
            pendingMatches = []
        }
    }

    private func searchDidEnd() {
        if cancelledSearches > 0 {
            cancelledSearches -= 1
            return
        }
        appendResults(pendingMatches)
        pendingMatches = []
        isSearching = false
    }
}
