//
//  BKHighlightStoreProtocol.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import Foundation

@MainActor
public protocol BKHighlightStoreProtocol: AnyObject {
    func save(_ highlight: BKHighlight) async
    func highlights(bookId: String) async -> [BKHighlight]
    func highlights(bookId: String, chapterId: String) async -> [BKHighlight]
    func delete(uuid: String) async
}
