//
//  BKPDFView.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import PDFKit
import SwiftUI
import BookKitCore

/// The PDF page view: one page at a time with horizontal paging, the Books-style selection menu
/// (colors first), a menu on tapped highlights, edge taps to turn pages and a center tap for the
/// reader controls.
final class BKPDFView: PDFView, @preconcurrency UIEditMenuInteractionDelegate {

    private enum Constants {
        static let edgeTapFraction: CGFloat = 0.2
    }

    weak var viewModel: BKPDFReaderViewModel?
    private lazy var highlightMenu = UIEditMenuInteraction(delegate: self)
    /// The highlight whose menu is showing.
    private var tappedHighlight: BKHighlight?
    /// Lets the tap work alongside PDFKit's gestures without changing how those behave.
    private let tapDelegate = BKSimultaneousGestureDelegate()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addInteraction(highlightMenu)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addInteraction(highlightMenu)
    }

    /// Adds the tap recognizer once PDFKit has installed its own (so double-tap zoom wins).
    func installTapHandling() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = tapDelegate
        tap.cancelsTouchesInView = false
        for doubleTap in Self.recognizers(in: self).compactMap({ $0 as? UITapGestureRecognizer })
            where doubleTap.numberOfTapsRequired == 2 {
            tap.require(toFail: doubleTap)
        }
        addGestureRecognizer(tap)
    }

    private static func recognizers(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap { recognizers(in: $0) }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let viewModel else { return }
        let point = recognizer.location(in: self)
        // A tap ends a selection without doing anything else.
        if let selection = currentSelection, !(selection.string ?? "").isEmpty {
            clearSelection()
            return
        }
        if let page = page(for: point, nearest: false),
           let highlight = viewModel.highlight(at: convert(point, to: page), on: page) {
            tappedHighlight = highlight
            highlightMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
            return
        }
        let x = point.x / max(bounds.width, 1)
        if x > 1 - Constants.edgeTapFraction {
            goToNextPage(nil)
        } else if x < Constants.edgeTapFraction {
            goToPreviousPage(nil)
        } else {
            viewModel.isChromeVisible.toggle()
        }
    }

    // MARK: - Selection menu

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let viewModel,
              let selection = currentSelection, let text = selection.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let colors = swatchRow { [weak viewModel] style, color in
            viewModel?.highlight(selection, style: style, color: color)
        }
        let search = UIAction(title: L("Search"), image: UIImage(systemName: "magnifyingglass")) { [weak viewModel] _ in
            viewModel?.searchBook(for: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        builder.insertChild(colors, atStartOfMenu: .root)
        builder.insertSibling(UIMenu(options: .displayInline, children: [search]), afterMenu: colors.identifier)
    }

    /// Every palette color as a swatch, in one row.
    private func swatchRow(apply: @escaping (BKAnnotationStyle, String) -> Void) -> UIMenu {
        let palettes = viewModel?.menuConfiguration.palettes ?? BKHighlightPalette.books
        let swatches = palettes.flatMap { palette in
            palette.colors.map { color in
                let symbol = palette.colors.count == 1 ? palette.style.systemImage : "circle.fill"
                // No title: the compact edit menu shows titles instead of images. VoiceOver reads the label.
                let image = UIImage(systemName: symbol)?
                    .withTintColor(UIColor(hex: color.hex) ?? .label, renderingMode: .alwaysOriginal)
                // Image-only menu items are read by their image's label.
                image?.accessibilityLabel = color.name
                let action = UIAction(title: "", image: image) { _ in
                    apply(palette.style, color.hex)
                }
                action.accessibilityLabel = color.name
                return action
            }
        }
        let identifier = UIMenu.Identifier("com.bookkit.pdf.colors")
        let row: UIMenu
        if #available(iOS 17.0, *) {
            row = UIMenu(identifier: identifier, options: [.displayInline, .displayAsPalette], children: swatches)
        } else {
            row = UIMenu(identifier: identifier, options: .displayInline, children: swatches)
        }
        row.preferredElementSize = .small
        return row
    }

    // MARK: - Highlight menu

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let highlight = tappedHighlight, let viewModel else { return nil }
        let colors = swatchRow { [weak viewModel] style, color in
            viewModel?.recolor(highlight, style: style, color: color)
        }
        let copy = UIAction(title: L("Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
            UIPasteboard.general.string = highlight.text
        }
        let remove = UIAction(title: L("Remove Highlight"), image: UIImage(systemName: "trash"),
                              attributes: .destructive) { [weak viewModel] _ in
            viewModel?.delete(highlight)
        }
        return UIMenu(children: [colors, UIMenu(options: .displayInline, children: [copy, remove])])
    }
}

private final class BKSimultaneousGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - SwiftUI

struct BKPDFContainer: UIViewRepresentable {

    @ObservedObject var viewModel: BKPDFReaderViewModel

    func makeUIView(context: Context) -> BKPDFView {
        let view = BKPDFView()
        view.viewModel = viewModel
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        view.document = viewModel.document
        view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 16])
        view.installTapHandling()
        viewModel.pdfView = view
        context.coordinator.observe(view, viewModel: viewModel)
        return view
    }

    func updateUIView(_ view: BKPDFView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        // Only touched on the main actor, and in deinit once nothing else can.
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        func observe(_ view: BKPDFView, viewModel: BKPDFReaderViewModel) {
            observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view,
                                                              queue: .main) { [weak view, weak viewModel] _ in
                MainActor.assumeIsolated {
                    guard let page = view?.currentPage, let viewModel else { return }
                    viewModel.pageDidChange(to: viewModel.document.index(for: page))
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
