//
//  BKComicReaderView.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import SwiftUI
import UIKit
import BookKitCore

/// Opens comic book archives (CBZ) in a page-by-page reader with zoom, bookmarks and a page grid.
public enum BKComicReaderViewBuilder {

    /// - Parameters:
    ///   - url: A `.cbz` file.
    ///   - bookId: Identifies the book in the stores; defaults to `BKComicBook.identifier`.
    ///   - onClose: Called by the reader's close button instead of `dismiss()`; set it when the reader
    ///     has a window of its own (e.g. `openWindow` on Mac). `nil` dismisses it.
    /// - Throws: When the file isn't a readable comic archive.
    @MainActor
    public static func build(url: URL,
                             bookId: String? = nil,
                             highlightStore: BKHighlightStoreProtocol? = nil,
                             positionStore: BKReadingPositionStoreProtocol? = nil,
                             onClose: (() -> Void)? = nil) throws -> BKComicReaderView {
        let book = try BKComicBook(url: url)
        let viewModel = BKComicReaderViewModel(book: book,
                                               bookId: bookId ?? book.identifier,
                                               highlightStore: highlightStore,
                                               positionStore: positionStore)
        return BKComicReaderView(viewModel: viewModel, onClose: onClose)
    }
}

public struct BKComicReaderView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var viewModel: BKComicReaderViewModel

    private let onClose: (() -> Void)?

    init(viewModel: BKComicReaderViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    /// The host's `onClose`, or dismiss (pushed or presented).
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var showsChrome: Bool {
        viewModel.isChromeVisible || voiceOverEnabled
    }

    public var body: some View {
        BKComicPager(viewModel: viewModel)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .top) { topChrome }
            .overlay(alignment: .bottom) { bottomChrome }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .statusBarHidden(!showsChrome)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $viewModel.showPages) {
                BKComicPagesView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showShare) {
                BKShareSheet(items: [BKShareFile.named(viewModel.book.fileURL, title: viewModel.book.title)])
                    .presentationDetents([.medium, .large])
            }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            BKChromeButton(systemImage: "xmark", accessibilityLabel: L("Close")) { close() }
            Spacer(minLength: 0)
            Text(viewModel.book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            BKChromeButton(systemImage: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                           accessibilityLabel: viewModel.isCurrentPageBookmarked ? L("Remove Bookmark") : L("Add Bookmark")) {
                viewModel.toggleBookmark()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: BKReaderChrome.topInset)
        .opacity(showsChrome ? 1 : 0)
        .allowsHitTesting(showsChrome)
        .accessibilityHidden(!showsChrome)
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
    }

    private var bottomChrome: some View {
        ZStack {
            BKComicPageSlider(viewModel: viewModel)
            HStack {
                Spacer()
                Menu {
                    Button {
                        viewModel.showShare = true
                    } label: {
                        Label(L("Share…"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        viewModel.showPages = true
                    } label: {
                        Label(L("Pages"), systemImage: "square.grid.2x2")
                    }
                } label: {
                    BKChromeButtonLabel(systemImage: "ellipsis")
                }
                .menuOrder(.fixed)
                .tint(.primary)
                .accessibilityLabel(L("Reader Menu"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: BKReaderChrome.bottomInset)
        .opacity(showsChrome ? 1 : 0)
        .allowsHitTesting(showsChrome)
        .accessibilityHidden(!showsChrome)
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
    }
}

/// Drag to any page; manga sliders run right to left.
private struct BKComicPageSlider: View {
    @ObservedObject var viewModel: BKComicReaderViewModel
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
            .environment(\.layoutDirection, viewModel.book.readsRightToLeft ? .rightToLeft : .leftToRight)
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

/// Every page as a thumbnail, or only the bookmarked ones.
private struct BKComicPagesView: View {
    @ObservedObject var viewModel: BKComicReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var bookmarksOnly = false

    private var pages: [Int] {
        bookmarksOnly
            ? viewModel.bookmarks.map(\.spineIndex).sorted()
            : Array(0..<viewModel.pageCount)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("Show"), selection: $bookmarksOnly) {
                    Text(L("Pages")).tag(false)
                    Text(L("Bookmarks")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        if pages.isEmpty {
                            Text(L("No Bookmarks"))
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                            ForEach(pages, id: \.self) { page in
                                Button {
                                    viewModel.go(toPage: page)
                                    dismiss()
                                } label: {
                                    BKComicThumbnail(viewModel: viewModel, page: page)
                                }
                                .buttonStyle(.plain)
                                .id(page)
                            }
                        }
                        .padding(16)
                    }
                    .onAppear { proxy.scrollTo(viewModel.pageIndex, anchor: .center) }
                }
            }
            .navigationTitle(viewModel.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L("Close"))
                }
            }
        }
    }
}

private struct BKComicThumbnail: View {
    @ObservedObject var viewModel: BKComicReaderViewModel
    let page: Int
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Rectangle().fill(.quaternary).aspectRatio(2 / 3, contentMode: .fit)
                    }
                }
                .frame(height: 140)
                .overlay {
                    if page == viewModel.pageIndex {
                        RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 3)
                    }
                }
                if viewModel.isBookmarked(page) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.red)
                        .padding(4)
                        .accessibilityLabel(L("Bookmarked"))
                }
            }
            Text("\(page + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L("Page %lld"), page + 1))
        .task(id: page) {
            image = await viewModel.image(page: page, maxPixelSize: 300)
        }
    }
}

// MARK: - Pager

struct BKComicPager: UIViewControllerRepresentable {
    @ObservedObject var viewModel: BKComicReaderViewModel

    func makeUIViewController(context: Context) -> BKComicPagerController {
        BKComicPagerController(viewModel: viewModel)
    }

    func updateUIViewController(_ controller: BKComicPagerController, context: Context) {}
}

/// Pages side by side with a slide between them; manga pages advance to the left.
final class BKComicPagerController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private let viewModel: BKComicReaderViewModel
    private let pageViewController = UIPageViewController(transitionStyle: .scroll,
                                                          navigationOrientation: .horizontal,
                                                          options: [.interPageSpacing: 12])
    private let tapDelegate = BKComicTapDelegate()

    init(viewModel: BKComicReaderViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var rightToLeft: Bool { viewModel.book.readsRightToLeft }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        pageViewController.dataSource = self
        pageViewController.delegate = self
        addChild(pageViewController)
        pageViewController.view.frame = view.bounds
        pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = tapDelegate
        view.addGestureRecognizer(tap)

        viewModel.showPage = { [weak self] page, animated in
            self?.show(page: page, animated: animated)
        }
        show(page: 0, animated: false)
        Task { [weak self] in
            guard let self else { return }
            let saved = await self.viewModel.load()
            if saved != 0 { self.show(page: saved, animated: false) }
        }
    }

    private func page(_ index: Int) -> BKComicPageViewController? {
        guard viewModel.book.pages.indices.contains(index) else { return nil }
        return BKComicPageViewController(index: index, viewModel: viewModel)
    }

    private func show(page index: Int, animated: Bool) {
        guard let controller = page(index) else { return }
        let current = (pageViewController.viewControllers?.first as? BKComicPageViewController)?.index ?? 0
        let forward = index >= current
        let direction: UIPageViewController.NavigationDirection = (forward != rightToLeft) ? .forward : .reverse
        pageViewController.setViewControllers([controller], direction: direction, animated: animated)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let x = recognizer.location(in: view).x / max(view.bounds.width, 1)
        // Edges turn the page; the leading edge goes back (the right edge for manga).
        if x > 0.8 {
            viewModel.go(toPage: viewModel.pageIndex + (rightToLeft ? -1 : 1))
        } else if x < 0.2 {
            viewModel.go(toPage: viewModel.pageIndex + (rightToLeft ? 1 : -1))
        } else {
            viewModel.isChromeVisible.toggle()
        }
    }

    // MARK: Data source

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = (viewController as? BKComicPageViewController)?.index else { return nil }
        return page(rightToLeft ? index + 1 : index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = (viewController as? BKComicPageViewController)?.index else { return nil }
        return page(rightToLeft ? index - 1 : index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let current = pageViewController.viewControllers?.first as? BKComicPageViewController else { return }
        viewModel.pageDidChange(to: current.index)
    }
}

/// Single taps wait for a page's double-tap zoom to fail.
private final class BKComicTapDelegate: NSObject, UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (otherGestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// One page: the image fitted to the screen, pinch or double-tap to zoom.
final class BKComicPageViewController: UIViewController, UIScrollViewDelegate {

    let index: Int
    private let viewModel: BKComicReaderViewModel
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var hasStartedLoading = false

    init(index: Int, viewModel: BKComicReaderViewModel) {
        self.index = index
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = String(format: L("Page %lld"), index + 1)
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        view.addSubview(spinner)
        spinner.startAnimating()

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasStartedLoading, view.bounds.width > 0 else { return }
        hasStartedLoading = true
        // Twice the page's size on screen, so zooming in stays sharp.
        let maxPixels = max(view.bounds.width, view.bounds.height) * traitCollection.displayScale * 2
        Task { [weak self] in
            guard let self else { return }
            let image = await self.viewModel.image(page: self.index, maxPixelSize: maxPixels)
            self.spinner.stopAnimating()
            self.imageView.image = image
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scrollView.setZoomScale(1, animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }
}
