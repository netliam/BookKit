//
//  BKReadingPosition.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation

/// The last place a reader was at in a book.
public struct BKReadingPosition: Codable, Sendable, Equatable {
    public let bookId: String
    public let spineIndex: Int
    /// Opaque location produced by the reader's JS (`getCoordFromNode`).
    public let coords: String
    public let chapterId: String
    public let dateUpdated: Double

    public init(bookId: String,
                spineIndex: Int,
                coords: String,
                chapterId: String,
                dateUpdated: Double = Date().timeIntervalSince1970) {
        self.bookId = bookId
        self.spineIndex = spineIndex
        self.coords = coords
        self.chapterId = chapterId
        self.dateUpdated = dateUpdated
    }
}

@MainActor
public protocol BKReadingPositionStoreProtocol: AnyObject {
    func save(position: BKReadingPosition) async
    func position(bookId: String) async -> BKReadingPosition?
}
