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
    case pdf
    /// Comic book archives (CBZ).
    case comic
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
        case .pdf: ["pdf"]
        case .comic: ["cbz"]
        case .plainText: ["txt", "text"]
        case .markdown: ["md", "markdown", "mdown", "mkd"]
        }
    }

    /// Types to pass to a document picker (`fileImporter(allowedContentTypes:)`).
    public var contentTypes: [UTType] {
        switch self {
        case .epub: [.epub]
        case .pdf: [.pdf]
        // iOS has no system type for .cbz: the app must declare one (see the README), else the
        // document picker greys these files out.
        case .comic: [UTType(BKBookFormat.comicTypeIdentifier) ?? UTType(filenameExtension: "cbz", conformingTo: .zip) ?? .zip]
        case .plainText: [.plainText]
        case .markdown: [UTType("net.daringfireball.markdown") ?? .plainText]
        }
    }

    /// The type an app declares (`UTImportedTypeDeclarations`) so CBZ files can be picked.
    public static let comicTypeIdentifier = "com.bookkit.cbz"

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
