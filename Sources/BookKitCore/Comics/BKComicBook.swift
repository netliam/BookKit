//
//  BKComicBook.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import CryptoKit
import Foundation

/// A comic book archive (CBZ): its page images in reading order and its ComicInfo.xml metadata.
/// Pages are read from the archive on demand.
public struct BKComicBook: Sendable {

    public let fileURL: URL
    /// Stable id from the file's contents, for the highlight and position stores.
    public let identifier: String
    public let title: String
    public let authors: [String]
    /// Manga: pages turn from right to left (ComicInfo `Manga` = `YesAndRightToLeft`).
    public let readsRightToLeft: Bool
    /// Archive paths of the page images, in reading order.
    public let pages: [String]

    private let archive: BKZipArchive

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff"]

    /// Opens `url` (a `.cbz`).
    public init(url: URL) throws {
        let archive = try BKZipArchive(url: url)
        let pages = archive.entries
            .map(\.path)
            .filter { path in
                let name = (path as NSString).lastPathComponent
                return !path.hasPrefix("__MACOSX/") && !name.hasPrefix(".")
                    && Self.imageExtensions.contains((name as NSString).pathExtension.lowercased())
            }
            // "page2" before "page10", like Finder.
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !pages.isEmpty else { throw BKBookError.unreadable("No page images in the archive") }

        let infoPath = archive.entries.first { ($0.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml" }?.path
        let info = infoPath.flatMap { try? archive.data(at: $0) }.map(BKComicInfo.init(data:)) ?? BKComicInfo()

        self.fileURL = url
        self.archive = archive
        self.pages = pages
        self.identifier = BKFileIdentifier.identifier(forFileAt: url, prefix: "comic")
        self.title = info.displayTitle ?? url.deletingPathExtension().lastPathComponent
        self.authors = info.authors
        self.readsRightToLeft = info.readsRightToLeft
    }

    /// The image file of page `index` (zero-based).
    public func imageData(page index: Int) throws -> Data {
        guard pages.indices.contains(index) else { throw BKZipArchive.ArchiveError.missingEntry("page \(index)") }
        return try archive.data(at: pages[index])
    }
}

/// The fields of ComicInfo.xml (the ComicRack schema) that BookKit uses.
struct BKComicInfo {
    var fields: [String: String] = [:]

    init() {}

    init(data: Data) {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        fields = delegate.fields
    }

    var displayTitle: String? {
        if let title = fields["Title"], !title.isEmpty {
            if let series = fields["Series"], !series.isEmpty, series != title {
                return "\(series): \(title)"
            }
            return title
        }
        guard let series = fields["Series"], !series.isEmpty else { return nil }
        if let number = fields["Number"], !number.isEmpty { return "\(series) #\(number)" }
        return series
    }

    var authors: [String] {
        ["Writer", "Penciller", "Artist"]
            .compactMap { fields[$0] }
            .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    var readsRightToLeft: Bool {
        fields["Manga"]?.caseInsensitiveCompare("YesAndRightToLeft") == .orderedSame
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var fields: [String: String] = [:]
        private var depth = 0
        private var current = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            depth += 1
            current = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            current += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            // Fields are the children of the root <ComicInfo>.
            if depth == 2 {
                let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { fields[elementName] = value }
            }
            depth -= 1
            current = ""
        }
    }
}

/// Stable identifiers for book files, from their contents: the same file always gets the same id,
/// wherever it's stored.
public enum BKFileIdentifier {
    /// A hash of the file's first 4 MB and its size, e.g. `comic-3f2a…`.
    public static func identifier(forFileAt url: URL, prefix: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "\(prefix)-\(url.lastPathComponent)" }
        defer { try? handle.close() }
        var hasher = SHA256()
        hasher.update(data: (try? handle.read(upToCount: 4 * 1024 * 1024)) ?? Data())
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        hasher.update(data: Data("\(size)".utf8))
        return "\(prefix)-" + hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
