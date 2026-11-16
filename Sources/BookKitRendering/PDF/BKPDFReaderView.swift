//
//  BKPDFReaderView.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import PDFKit
import SwiftUI
import CryptoKit
import BookKitCore

/// Opens PDFs in a Books-style reader: full-screen pages, controls on tap, bookmarks, colored
/// highlights, contents (the PDF's outline), search and share.
public enum BKPDFReaderViewBuilder {

    /// - Parameters:
    ///   - url: A PDF file.
    ///   - bookId: Identifies the book in the stores; defaults to a hash of the file's contents.
    ///   - highlightStore: Where highlights and bookmarks are saved (e.g. a `BKJSONReaderStore`).
    ///   - positionStore: Where the reading position is saved.
    /// - Returns: The reader, or `nil` when the file isn't a readable PDF (e.g. it's encrypted).
    @MainActor
    public static func build(url: URL,
                             bookId: String? = nil,
                             highlightStore: BKHighlightStoreProtocol? = nil,
                             positionStore: BKReadingPositionStoreProtocol? = nil,
                             menuConfiguration: BKHighlightMenuConfiguration = BKHighlightMenuConfiguration()) -> BKPDFReaderView? {
        guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
        let viewModel = BKPDFReaderViewModel(document: document,
                                             fileURL: url,
                                             bookId: bookId ?? identifier(forPDFAt: url),
                                             highlightStore: highlightStore,
                                             positionStore: positionStore,
                                             menuConfiguration: menuConfiguration)
        return BKPDFReaderView(viewModel: viewModel)
    }

    /// A stable id from the file's contents (its first 4 MB and size), for the stores.
    public static func identifier(forPDFAt url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return url.lastPathComponent }
        defer { try? handle.close() }
        var hasher = SHA256()
        hasher.update(data: (try? handle.read(upToCount: 4 * 1024 * 1024)) ?? Data())
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        hasher.update(data: Data("\(size)".utf8))
        return "pdf-" + hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

public struct BKPDFReaderView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var viewModel: BKPDFReaderViewModel

    init(viewModel: BKPDFReaderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var showsChrome: Bool {
        viewModel.isChromeVisible || voiceOverEnabled
    }

    public var body: some View {
        BKPDFContainer(viewModel: viewModel)
            .ignoresSafeArea()
            .overlay(alignment: .top) { topChrome }
            .overlay(alignment: .bottom) { bottomChrome }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .statusBarHidden(!showsChrome)
            .sheet(isPresented: $viewModel.showContents) {
                BKContentsView(entries: viewModel.contentsEntries,
                               currentSpineIndex: viewModel.pageIndex,
                               pageNumber: { entry in entry.spineIndex.map { $0 + 1 } },
                               markPageNumber: { $0.spineIndex + 1 },
                               bookByline: viewModel.title,
                               highlightMenu: viewModel.menuConfiguration,
                               highlightsProvider: { [viewModel] in viewModel.marks },
                               onSelectEntry: { viewModel.navigate(to: $0) },
                               onSelectMark: { viewModel.navigate(to: $0) })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showSearch) {
                BKPDFSearchView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showShare) {
                BKShareSheet(items: viewModel.shareItems)
                    .presentationDetents([.medium, .large])
            }
            .task { await viewModel.load() }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        ZStack {
            Text(viewModel.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, BKReaderChrome.buttonSize + 28)
                .opacity(showsChrome ? 0 : 1)
                .accessibilityHidden(showsChrome)
            HStack(spacing: 12) {
                BKChromeButton(systemImage: "xmark", accessibilityLabel: L("Close")) { dismiss() }
                Spacer(minLength: 0)
                Text(viewModel.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                BKChromeButton(systemImage: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                               accessibilityLabel: viewModel.isCurrentPageBookmarked ? L("Remove Bookmark") : L("Add Bookmark")) {
                    viewModel.toggleBookmark()
                }
            }
            .padding(.horizontal, 16)
            .opacity(showsChrome ? 1 : 0)
            .allowsHitTesting(showsChrome)
            .accessibilityHidden(!showsChrome)
        }
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
        .frame(height: BKReaderChrome.topInset)
    }

    private var bottomChrome: some View {
        ZStack {
            Text(viewModel.pageText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .opacity(showsChrome ? 0 : 1)
                .accessibilityHidden(showsChrome)
            ZStack {
                BKPDFPageSlider(viewModel: viewModel)
                HStack {
                    Spacer()
                    menu
                }
            }
            .padding(.horizontal, 16)
            .opacity(showsChrome ? 1 : 0)
            .allowsHitTesting(showsChrome)
            .accessibilityHidden(!showsChrome)
        }
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
        .frame(height: BKReaderChrome.bottomInset)
    }

    private var menu: some View {
        Menu {
            Button {
                viewModel.showShare = true
            } label: {
                Label(L("Share…"), systemImage: "square.and.arrow.up")
            }
            Button {
                viewModel.showContents = true
            } label: {
                Label(L("Contents"), systemImage: "list.bullet.rectangle.portrait")
            }
            Button {
                viewModel.showSearch = true
            } label: {
                Label(L("Search Book"), systemImage: "magnifyingglass")
            }
        } label: {
            BKChromeButtonLabel(systemImage: "ellipsis")
        }
        .menuOrder(.fixed)
        .tint(.primary)
        .accessibilityLabel(L("Reader Menu"))
    }
}

/// Drag to any page; the page opens when the slider is released.
private struct BKPDFPageSlider: View {
    @ObservedObject var viewModel: BKPDFReaderViewModel
    @State private var dragPage: Double?

    var body: some View {
        let last = Double(max(viewModel.pageCount - 1, 1))
        VStack(spacing: 6) {
            Slider(value: Binding(get: { dragPage ?? Double(viewModel.pageIndex) },
                                  set: { dragPage = $0.rounded() }),
                   in: 0...last) { editing in
                if !editing, let dragPage {
                    viewModel.go(toPage: Int(dragPage))
                    self.dragPage = nil
                }
            }
            .tint(.secondary)
            .frame(width: 220)
            Text(dragPage.map { String(format: L("%lld of %lld"), Int($0) + 1, viewModel.pageCount) } ?? viewModel.pageText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Progress"))
        .accessibilityValue(viewModel.pageText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: viewModel.go(toPage: viewModel.pageIndex + 1)
            case .decrement: viewModel.go(toPage: viewModel.pageIndex - 1)
            @unknown default: break
            }
        }
    }
}

/// Search sheet: matches with their page and surrounding text.
private struct BKPDFSearchView: View {
    @ObservedObject var viewModel: BKPDFReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.isSearching, !viewModel.searchQuery.isEmpty, viewModel.searchResults.isEmpty {
                    Text(L("No Results"))
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.searchResults) { result in
                    Button {
                        viewModel.select(result)
                    } label: {
                        HStack(alignment: .top) {
                            Text(result.snippet)
                                .font(.subheadline)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text("\(result.pageIndex + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(String(format: L("Page %lld"), result.pageIndex + 1))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isSearching && viewModel.searchResults.isEmpty {
                    ProgressView()
                }
            }
            .searchable(text: Binding(get: { viewModel.searchQuery },
                                      set: { if $0 != viewModel.searchQuery { viewModel.search($0) } }),
                        placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(L("Search Book"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Close")) { dismiss() }
                }
            }
        }
    }
}
