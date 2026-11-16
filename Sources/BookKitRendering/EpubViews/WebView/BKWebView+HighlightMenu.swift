//
//  BKWebView+HighlightMenu.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit
import BookKitCore

extension Notification.Name {
    /// Posted when a highlight is saved, so pages showing it redraw its color and note marker.
    /// `userInfo[BKHighlight.notificationKey]` is the saved `BKHighlight`.
    static let bkHighlightDidChange = Notification.Name("BKHighlightDidChange")
}

extension BKHighlight {
    static let notificationKey = "highlight"
}

/// The menu for a tapped highlight (see `highlightMenuElements`), shown over it with a
/// `UIEditMenuInteraction`.
@MainActor
final class BKHighlightMenu: NSObject, @preconcurrency UIEditMenuInteractionDelegate {

    let highlight: BKHighlight
    let rect: CGRect
    private let elements: [UIMenuElement]
    private(set) lazy var interaction = UIEditMenuInteraction(delegate: self)

    init(highlight: BKHighlight, rect: CGRect, elements: [UIMenuElement]) {
        self.highlight = highlight
        self.rect = rect
        self.elements = elements
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: elements)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        rect
    }
}

extension BKWebView {

    /// Shows the menu for `highlight`, which was tapped at `rect` (this view's coordinates).
    func showHighlightMenu(for highlight: BKHighlight, at rect: CGRect) {
        if let old = highlightMenu {
            old.interaction.dismissMenu()
            removeInteraction(old.interaction)
        }
        let menu = BKHighlightMenu(highlight: highlight, rect: rect, elements: highlightMenuElements(for: highlight))
        highlightMenu = menu
        addInteraction(menu.interaction)
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY))
        menu.interaction.presentEditMenu(with: configuration)
    }

    /// The tapped highlight's styles and colors (its own checked), then the host's highlight actions.
    func highlightMenuElements(for highlight: BKHighlight) -> [UIMenuElement] {
        paletteElements(current: highlight) { [weak self] style, color in
            self?.restyle(highlight, style: style, color: color)
        } + actionElements(menuConfiguration.highlightActions, highlight: highlight, systemLookUp: [])
    }

    /// The selection's styles and colors, then the host's selection actions.
    func selectionMenuElements(systemLookUp: [UIMenuElement]) -> [UIMenuElement] {
        paletteElements(current: nil) { [weak self] style, color in
            self?.highlightSelection(style: style, color: color)
        } + actionElements(menuConfiguration.selectionActions, highlight: nil, systemLookUp: systemLookUp)
    }

    /// The reader's configuration (the default before the view model is set).
    private var readerConfiguration: BKReaderConfiguration {
        viewModel?.configuration ?? BKReaderConfiguration()
    }

    var menuConfiguration: BKHighlightMenuConfiguration {
        readerConfiguration.highlightMenu
    }

    /// The style and color to annotate with when none is picked (Add Note): the last ones used, if
    /// still offered, else the first offered.
    func currentLook() -> (style: BKAnnotationStyle, color: String) {
        let menu = menuConfiguration
        let defaults = readerConfiguration.defaults
        guard let palette = defaults.getLastAnnotationStyle().flatMap(menu.palette(for:))
                ?? menu.palettes.first(where: { !$0.colors.isEmpty }) else {
            return (.highlight, BKHighlightStyle.yellow.color)
        }
        let last = defaults.getLastHighlightColor(for: palette.style)
        let color = palette.colors.first { last.map($0.matches) ?? false } ?? palette.colors[0]
        return (palette.style, color.hex)
    }

    // MARK: Styles and colors

    /// A row with the colors of the current style and each single-color style, then, if other
    /// styles have several colors, a submenu to pick from those.
    private func paletteElements(current: BKHighlight?,
                                 apply: @escaping (BKAnnotationStyle, String) -> Void) -> [UIMenuElement] {
        let palettes = menuConfiguration.palettes.filter { !$0.colors.isEmpty }
        guard !palettes.isEmpty else { return [] }
        let multi = palettes.filter { $0.colors.count > 1 }
        let singles = palettes.filter { $0.colors.count == 1 }
        let activeStyle = current?.annotationStyle ?? currentLook().style
        let active = multi.first { $0.style == activeStyle } ?? multi.first

        func isCurrent(_ style: BKAnnotationStyle, _ color: BKHighlightColor) -> Bool {
            current.map { $0.annotationStyle == style && color.matches($0.color) } ?? false
        }
        func swatch(_ palette: BKHighlightPalette, _ color: BKHighlightColor) -> UIAction {
            let checked = isCurrent(palette.style, color)
            let image = checked
                ? UIImage(systemName: "checkmark.circle.fill")
                : UIImage(systemName: palette.colors.count == 1 ? palette.style.systemImage : "circle.fill")
            // No title: the compact edit menu shows titles instead of images. VoiceOver reads the label.
            let tinted = image?.withTintColor(UIColor(hex: color.hex) ?? .label, renderingMode: .alwaysOriginal)
            let label = checked ? String(format: L("%@, current"), color.name) : color.name
            // Image-only menu items are read by their image's label.
            tinted?.accessibilityLabel = label
            let action = UIAction(title: "", image: tinted) { _ in
                apply(palette.style, color.hex)
            }
            // No `.on` state: the menu would draw its own tint-colored check over the swatch.
            action.accessibilityLabel = label
            return action
        }

        let swatches = (active.map { palette in palette.colors.map { swatch(palette, $0) } } ?? [])
            + singles.map { swatch($0, $0.colors[0]) }
        let row: UIMenu
        if #available(iOS 17.0, *) {
            row = UIMenu(options: [.displayInline, .displayAsPalette], children: swatches)
        } else {
            row = UIMenu(options: .displayInline, children: swatches)
        }
        row.preferredElementSize = .small

        let others = multi.filter { $0.style != active?.style }.map { palette in
            UIMenu(title: palette.style.menuTitle, image: UIImage(systemName: palette.style.systemImage),
                   children: palette.colors.map { color in
                UIAction(title: color.name,
                         image: UIImage(systemName: "circle.fill")?.withTintColor(UIColor(hex: color.hex) ?? .label,
                                                                                  renderingMode: .alwaysOriginal),
                         state: isCurrent(palette.style, color) ? .on : .off) { _ in
                    apply(palette.style, color.hex)
                }
            })
        }
        guard !others.isEmpty else { return [row] }
        let switcher = others.count == 1
            ? others[0]
            : UIMenu(title: L("Style"), image: UIImage(systemName: "textformat"), children: others)
        return [row, UIMenu(options: .displayInline, children: [switcher])]
    }

    private func restyle(_ highlight: BKHighlight, style: BKAnnotationStyle, color: String) {
        guard style != highlight.annotationStyle || color.caseInsensitiveCompare(highlight.color) != .orderedSame else { return }
        viewModel.configuration.defaults.setLastHighlight(style: style, color: color)
        var updated = highlight
        updated.annotationStyle = style
        updated.color = color
        updated.dateUpdated = Date().timeIntervalSince1970
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateDrawnHighlight(updated)
            // Saving tells the other pages (see `.bkHighlightDidChange`).
            await self.viewModel.saveHighlight(updated)
        }
    }

    // MARK: Actions

    /// The actions in order, in sections: Note and Delete stand alone, the others are grouped.
    private func actionElements(_ actions: [BKHighlightAction],
                                highlight: BKHighlight?,
                                systemLookUp: [UIMenuElement]) -> [UIMenuElement] {
        var sections: [[UIMenuElement]] = []
        var group: [UIMenuElement] = []
        for action in actions {
            let items = menuItems(for: action, highlight: highlight, systemLookUp: systemLookUp)
            guard !items.isEmpty else { continue }
            if action.standsAlone {
                if !group.isEmpty { sections.append(group) }
                group = []
                sections.append(items)
            } else {
                group += items
            }
        }
        if !group.isEmpty { sections.append(group) }
        return sections.map { UIMenu(options: .displayInline, children: $0) }
    }

    /// The menu items for one action, on the tapped `highlight` or (when `nil`) the selection.
    private func menuItems(for action: BKHighlightAction,
                           highlight: BKHighlight?,
                           systemLookUp: [UIMenuElement]) -> [UIMenuElement] {
        switch action {
        case .note:
            let hasNote = highlight?.hasNote ?? false
            return [UIAction(title: hasNote ? L("Edit Note") : L("Add Note"),
                             image: UIImage(systemName: hasNote ? "note.text" : "note.text.badge.plus")) { [weak self] _ in
                if let highlight { self?.viewModel.showNoote(highlight: highlight) } else { self?.addNoteToSelection() }
            }]
        case .copy:
            return [UIAction(title: L("Copy"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                if let highlight { UIPasteboard.general.string = highlight.text } else { self?.copySelection() }
            }]
        case .share:
            return [UIAction(title: L("Share…"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                if let highlight { self?.share(highlight) } else { self?.shareSelection() }
            }]
        case .search:
            guard readerConfiguration.showsSearch else { return [] }
            return [UIAction(title: L("Search"), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                if let highlight { self?.viewModel.searchBook(for: highlight.text) } else { self?.searchBookForSelection() }
            }]
        case .lookUp:
            // For a selection, Look Up and Translate come from the system (there's no public
            // Translate API); its "Search Web" gives way to searching the book.
            if highlight == nil, !systemLookUp.isEmpty { return systemLookUp }
            return [UIAction(title: L("Look Up"), image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
                if let highlight { self?.lookUp(highlight.text) } else { self?.lookUpSelection() }
            }]
        case .delete:
            guard let highlight else { return [] }
            return [UIAction(title: highlight.hasNote ? L("Delete Highlight and Note") : L("Delete Highlight"),
                             image: UIImage(systemName: "trash"),
                             attributes: .destructive) { [weak self] _ in
                self?.delete(highlight)
            }]
        case .custom(let custom):
            return [UIAction(title: custom.title, image: custom.systemImage.flatMap { UIImage(systemName: $0) }) { [weak self] _ in
                self?.run(custom, on: highlight)
            }]
        }
    }

    /// Gives a custom action the text and where it is, coords and CFI.
    func run(_ action: BKCustomHighlightAction, on highlight: BKHighlight?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let text: String
            let coords: String
            if let highlight {
                text = highlight.text
                coords = highlight.coords
            } else {
                guard let selected = await self.selectedText(), let selection = await self.getCoordsFromSelection() else { return }
                text = selected
                coords = selection
                await self.clearJSSelection()
            }
            let spineIndex = highlight?.spineIndex ?? self.viewModel.currentSpineIndex
            var cfi: String?
            if let book = self.viewModel.currentBook {
                // Off screen: this page has highlights drawn, which CFIs don't count.
                cfi = await BKCFIConverter(book: book).cfi(fromCoords: coords, spineIndex: spineIndex)
            }
            action.handler(BKHighlightActionContext(text: text, spineIndex: spineIndex, coords: coords,
                                                    cfi: cfi, highlight: highlight))
        }
    }

    private func lookUp(_ text: String) {
        parentViewController?.present(UIReferenceLibraryViewController(term: text), animated: true)
    }

    private func delete(_ highlight: BKHighlight) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.deleteHighlight(uuid: highlight.uuid)
            await self.removeHighlight(uuid: highlight.uuid)
        }
    }

    private func share(_ highlight: BKHighlight) {
        guard let presenter = parentViewController else { return }
        let item = viewModel.currentBook?.shareText(quoting: highlight.text) ?? highlight.text
        let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = self
        activity.popoverPresentationController?.sourceRect = highlightMenu?.rect
            ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        presenter.present(activity, animated: true)
    }
}

extension BKHighlightAction {
    /// Note and Delete get a section of their own.
    var standsAlone: Bool {
        switch self {
        case .note, .delete: true
        default: false
        }
    }
}

extension BKWebView {
    /// Whether a highlight or a link is under `point` (in `view`'s coordinates), in whichever
    /// reader web view is there, so the tap isn't also a page tap.
    static func hasHighlight(at point: CGPoint, in view: UIView) async -> Bool {
        var hit = view.hitTest(point, with: nil)
        while let current = hit, !(current is BKWebView) {
            hit = current.superview
        }
        guard let webView = hit as? BKWebView else { return false }
        return await webView.hasHighlight(at: view.convert(point, to: webView))
    }
}
