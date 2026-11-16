//
//  BKWebViewProtocols.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 26/11/25.
//

import Foundation
import BookKitCore

@MainActor
protocol BKWebViewModelProtocol {
    func showNoote(highlight: BKHighlight)
    /// Opens the book search with `text` (the selection menu's Search).
    func searchBook(for text: String)
    /// Follows a link that isn't a footnote: another place in the book, or a web page.
    func openLink(_ url: URL)
    func saveHighlight(_ highlight: BKHighlight) async
    func loadHighlights() async -> [BKHighlight]
    func deleteHighlight(uuid: String) async
    var currentBookId: String { get }
    var currentChapterId: String { get }
    var currentSpineIndex: Int { get }
    /// The book being read, for sharing a passage with its title.
    var currentBook: BKEpubBook? { get }
    var configuration: BKReaderConfiguration { get }
    var refresh: (() -> Void)? { get set }
}

@MainActor
protocol BKWebViewRouterProtocol {
    func showNoote(highlight: BKHighlight)
    /// Opens the book search with `text` (the selection menu's Search).
    func searchBook(for text: String)
    /// Follows a link that isn't a footnote: another place in the book, or a web page.
    func openLink(_ url: URL)
    func saveHighlight(_ highlight: BKHighlight) async
    func loadHighlights() async -> [BKHighlight]
    func deleteHighlight(uuid: String) async
    var currentBookId: String { get }
    var currentChapterId: String { get }
    var currentSpineIndex: Int { get }
    /// The book being read, for sharing a passage with its title.
    var currentBook: BKEpubBook? { get }
    var configuration: BKReaderConfiguration { get }
}
