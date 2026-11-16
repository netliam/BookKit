//
//  BKBookFormat.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import UniformTypeIdentifiers

/// The kinds of book file BookKit can open.
public enum BKBookFormat: String, CaseIterable, Sendable {
    case epub
    case plainText
    case markdown

    /// Detects the format from the file's extension.
    public init?(fileURL: URL) {
        let ext = fileURL.pathExtension.lowercased()
        guard let format = Self.allCases.first(where: { $0.fileExtensions.contains(ext) }) else { return nil }
        self = format
    }

    /// Lowercased file extensions of this format.
    public var fileExtensions: [String] {
        switch self {
        case .epub: ["epub"]
        case .plainText: ["txt", "text"]
        case .markdown: ["md", "markdown", "mdown", "mkd"]
        }
    }

    /// Types to pass to a document picker (`fileImporter(allowedContentTypes:)`).
    public var contentTypes: [UTType] {
        switch self {
        case .epub: [.epub]
        case .plainText: [.plainText]
        case .markdown: [UTType("net.daringfireball.markdown") ?? .plainText]
        }
    }

    /// Every type BookKit can open, for a document picker.
    public static var allContentTypes: [UTType] {
        allCases.flatMap(\.contentTypes)
    }
}

/// Errors from opening or converting a book file.
public enum BKBookError: Error, Equatable {
    /// The file's extension isn't one of `BKBookFormat`'s.
    case unsupportedFormat(String)
    /// The file couldn't be read or decoded as text.
    case unreadable(String)
}
