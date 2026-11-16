//
//  BKMobiConverter.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import BookKitCore

/// Turns unencrypted Kindle books (MOBI and AZW3/KF8) into an EPUB-style folder for the reader.
///
/// - MOBI 6: the HTML is split at its page breaks; `filepos` links become anchors and `recindex`
///   images become files.
/// - KF8: each part is rebuilt from its skeleton and fragments (the SKEL and FRAG indexes), and
///   `kindle:embed`, `kindle:flow` and `kindle:pos` references are resolved to files and anchors.
///
/// The table of contents comes from the book's NCX index in both cases.
public enum BKMobiConverter {

    /// Bump when the generated layout changes (see `BKTextBookConverter.layoutVersion`).
    static let layoutVersion = 1

    public static func convert(_ fileURL: URL, to destination: URL) throws -> BKEpubBook {
        guard BKBookFormat(fileURL: fileURL) == .mobi else {
            throw BKBookError.unsupportedFormat(fileURL.pathExtension)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw BKBookError.unreadable(error.localizedDescription)
        }
        var writer = try package(from: data, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
        writer.identifier = BKEpubPackageWriter.identifier(for: data + Data("bookkit-mobi-\(layoutVersion)".utf8))
        try writer.write(to: destination)
        return try BKEpubParser.parse(from: destination)
    }

    static func package(from data: Data, fallbackTitle: String) throws -> BKEpubPackageWriter {
        let file = try BKMobiFile(data: data)
        let header = try file.readableHeader()
        let text = try file.text(for: header)
        var resources = Resources(file: file, header: header)

        let title = header.exthString(503) ?? (header.fullName.isEmpty ? nil : header.fullName) ?? fallbackTitle
        var writer = BKEpubPackageWriter(title: title, authors: header.exthStrings(100),
                                         identifier: "", chapters: [])
        writer.language = header.exthString(524) ?? "und"

        if header.isKF8 {
            try KF8(file: file, header: header, text: text).build(into: &writer, resources: &resources)
        } else {
            Mobi6(file: file, header: header, text: text).build(into: &writer, resources: &resources)
        }
        if writer.chapters.isEmpty {
            throw BKBookError.unreadable("The Kindle book has no text")
        }
        if let cover = header.exthInt(201), let href = resources.href(forResource: cover + 1) {
            writer.coverHref = href
        }
        writer.resources += resources.written
        return writer
    }

    // MARK: - Resources

    /// Images and fonts, numbered from 1 after the book's first image record; written on first use.
    struct Resources {
        let file: BKMobiFile
        let header: BKMobiFile.Header
        private(set) var written: [BKEpubPackageWriter.Resource] = []
        private var hrefs: [Int: String] = [:]

        init(file: BKMobiFile, header: BKMobiFile.Header) {
            self.file = file
            self.header = header
        }

        /// Package href of resource `number` (1-based), or `nil` when it isn't an image or font.
        mutating func href(forResource number: Int) -> String? {
            if let href = hrefs[number] { return href }
            guard number >= 1, let first = header.absolute(header.firstImageIndex) else { return nil }
            let record = file.record(first + number - 1)
            guard let (data, ext, folder) = Self.decode(record) else { return nil }
            let href = String(format: "%@/resource%05d.%@", folder, number, ext)
            written.append(.init(href: href, data: data))
            hrefs[number] = href
            return href
        }

        static func decode(_ record: Data) -> (Data, String, String)? {
            let bytes = [UInt8](record.prefix(8))
            guard bytes.count >= 4 else { return nil }
            if bytes.starts(with: [0xFF, 0xD8]) { return (record, "jpg", "images") }
            if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (record, "png", "images") }
            if bytes.starts(with: [0x47, 0x49, 0x46]) { return (record, "gif", "images") }
            if bytes.starts(with: [0x42, 0x4D]) { return (record, "bmp", "images") }
            if bytes.starts(with: Array("FONT".utf8)), let font = decodeFont(record) {
                let ext = font.prefix(4) == Data("OTTO".utf8) ? "otf" : "ttf"
                return (font, ext, "fonts")
            }
            return nil
        }

        /// KF8 font records: optionally XOR-obfuscated, optionally zlib-compressed.
        static func decodeFont(_ record: Data) -> Data? {
            guard record.count >= 24 else { return nil }
            let size = Int(record.bigUInt32(at: 4)), flags = Int(record.bigUInt32(at: 8))
            let start = Int(record.bigUInt32(at: 12))
            let xorLength = Int(record.bigUInt32(at: 16)), xorStart = Int(record.bigUInt32(at: 20))
            guard start <= record.count else { return nil }
            var font = [UInt8](record.subdata(in: start..<record.count))
            if flags & 0x2 != 0, xorLength > 0, xorStart + xorLength <= record.count {
                let key = [UInt8](record.subdata(in: xorStart..<(xorStart + xorLength)))
                for index in 0..<min(1040, font.count) { font[index] ^= key[index % xorLength] }
            }
            if flags & 0x1 != 0 {
                // zlib: a 2-byte header, then raw DEFLATE.
                guard font.count > 2 else { return nil }
                return try? BKZipArchive.inflate(Data(font.dropFirst(2)), expectedSize: size)
            }
            return Data(font)
        }
    }

    // MARK: - NCX

    struct NCXEntry {
        let title: String
        let depth: Int
        /// MOBI 6: a byte position in the text.
        let position: Int?
        /// KF8: fragment number and offset.
        let fid: (Int, Int)?
    }

    static func ncx(file: BKMobiFile, header: BKMobiFile.Header) -> [NCXEntry] {
        guard let index = header.absolute(header.ncxIndex) else { return [] }
        let (entries, strings) = file.index(at: index)
        return entries.compactMap { entry in
            guard let nameOffset = entry.tags[3]?.first, let name = strings[nameOffset] else { return nil }
            let title = String(data: name, encoding: .utf8) ?? String(data: name, encoding: .windowsCP1252) ?? ""
            let fid = entry.tags[6].flatMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }
            return NCXEntry(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            depth: entry.tags[4]?.first ?? 0,
                            position: entry.tags[1]?.first,
                            fid: fid)
        }
    }

    /// Nests flat NCX entries by depth.
    static func nest(_ flat: [(entry: NCXEntry, target: (chapter: Int, fragment: String?))]) -> [BKEpubPackageWriter.TOCEntry] {
        var roots: [BKEpubPackageWriter.TOCEntry] = []
        var stack: [(depth: Int, path: [Int])] = []
        for item in flat where !item.entry.title.isEmpty {
            let node = BKEpubPackageWriter.TOCEntry(title: item.entry.title, chapterIndex: item.target.chapter,
                                                    fragment: item.target.fragment)
            while let last = stack.last, last.depth >= item.entry.depth { stack.removeLast() }
            if let parent = stack.last {
                let path = parent.path
                roots.append(at: path, child: node)
                stack.append((item.entry.depth, path + [roots.childCount(at: path) - 1]))
            } else {
                roots.append(node)
                stack.append((item.entry.depth, [roots.count - 1]))
            }
        }
        return roots
    }

    // MARK: - Shared helpers

    static let base32Digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUV")

    static func base32(_ string: Substring) -> Int {
        string.uppercased().reduce(0) { $0 * 32 + (base32Digits.firstIndex(of: $1) ?? 0) }
    }

    /// Replaces each match of `pattern`; `transform` gets the capture groups (group 0 is the match).
    static func replace(_ pattern: String, in string: String, options: NSRegularExpression.Options = [.caseInsensitive],
                        _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return string }
        let nsString = string as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: nsString.length)) {
            result += nsString.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform((0..<match.numberOfRanges).map { group in
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : nsString.substring(with: range)
            })
            last = match.range.location + match.range.length
        }
        return result + nsString.substring(from: last)
    }

    /// Moves `position` (in `text`) out of any tag it falls inside, to just after that tag.
    static func outsideTag(_ position: Int, in text: NSString) -> Int {
        let before = text.substring(to: min(position, text.length)) as NSString
        let lastOpen = before.range(of: "<", options: .backwards).location
        let lastClose = before.range(of: ">", options: .backwards).location
        guard lastOpen != NSNotFound, lastClose == NSNotFound || lastOpen > lastClose else { return position }
        let close = text.range(of: ">", range: NSRange(location: position, length: text.length - position)).location
        return close == NSNotFound ? position : close + 1
    }

    /// Text of the first heading in `html`, without tags.
    static func firstHeading(_ html: String) -> String? {
        guard let range = html.range(of: #"<h[1-3][^>]*>(.*?)</h[1-3]>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let text = String(html[range])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private extension Array where Element == BKEpubPackageWriter.TOCEntry {
    mutating func append(at path: [Int], child: Element) {
        guard let first = path.first else { return }
        if path.count == 1 {
            self[first].children.append(child)
        } else {
            self[first].children.append(at: Array<Int>(path.dropFirst()), child: child)
        }
    }

    func childCount(at path: [Int]) -> Int {
        guard let first = path.first else { return count }
        return path.count == 1 ? self[first].children.count : self[first].children.childCount(at: Array<Int>(path.dropFirst()))
    }
}

// MARK: - MOBI 6

private struct Mobi6 {
    let file: BKMobiFile
    let header: BKMobiFile.Header
    let text: Data

    func build(into writer: inout BKEpubPackageWriter, resources: inout BKMobiConverter.Resources) {
        // Latin-1 keeps one character per byte, so string offsets are the text's byte positions.
        var html = (String(data: text, encoding: .isoLatin1) ?? "") as NSString
        let ncx = BKMobiConverter.ncx(file: file, header: header)

        // Anchors where links and contents entries point, inserted from the end so positions hold.
        var targets = Set(ncx.compactMap(\.position))
        let fileposPattern = try? NSRegularExpression(pattern: #"filepos=["']?0*(\d+)"#, options: .caseInsensitive)
        for match in fileposPattern?.matches(in: html as String, range: NSRange(location: 0, length: html.length)) ?? [] {
            if let value = Int(html.substring(with: match.range(at: 1))) { targets.insert(value) }
        }
        let mutable = NSMutableString(string: html)
        for target in targets.sorted(by: >) where target <= mutable.length {
            var position = BKMobiConverter.outsideTag(target, in: mutable)
            // An anchor at a page break belongs to the page after it.
            let rest = mutable.substring(from: position) as NSString
            if rest.hasPrefix("<mbp:pagebreak") || rest.hasPrefix("<MBP:PAGEBREAK") {
                let close = rest.range(of: ">").location
                if close != NSNotFound { position += close + 1 }
            }
            mutable.insert("<a id=\"filepos\(target)\"></a>", at: position)
        }
        html = mutable

        // Back to real text in the book's encoding.
        let bytes = (html as String).data(using: .isoLatin1) ?? Data()
        var body = (header.encoding == 65001 ? String(data: bytes, encoding: .utf8) : nil)
            ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
        if let open = body.range(of: #"<body[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            body = String(body[open.upperBound...])
        }
        if let close = body.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            body = String(body[..<close.lowerBound])
        }

        // Chapters at page breaks; Mobipocket's own tags go.
        var parts = body.components(separatedBy: "\u{0}")
        if let breaks = try? NSRegularExpression(pattern: #"<mbp:pagebreak[^>]*>"#, options: .caseInsensitive) {
            let marked = breaks.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body),
                                                         withTemplate: "\u{0}")
            parts = marked.components(separatedBy: "\u{0}")
        }
        parts = parts
            .map { $0.replacingOccurrences(of: #"</?mbp:[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive]) }
            .filter { !$0.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.range(of: "<img", options: .caseInsensitive) != nil }

        // Which chapter each anchor ended up in.
        var anchorChapter: [Int: Int] = [:]
        for (index, part) in parts.enumerated() {
            for match in part.matches(of: #/id="filepos(\d+)"/#) {
                if let value = Int(match.1) { anchorChapter[value] = index }
            }
        }

        for (index, part) in parts.enumerated() {
            var chapter = part
            chapter = BKMobiConverter.replace(#"filepos=["']?0*(\d+)["']?"#, in: chapter) { groups in
                guard let target = Int(groups[1]), let targetChapter = anchorChapter[target] else { return "href=\"#\"" }
                let file = (writer.chapterHref(targetChapter) as NSString).lastPathComponent
                return "href=\"\(file)#filepos\(target)\""
            }
            chapter = BKMobiConverter.replace(#"(?:hi|lo)?recindex=["']?(\d+)["']?"#, in: chapter) { groups in
                guard let number = Int(groups[1]), let href = resources.href(forResource: number) else { return "" }
                return "src=\"../\(href)\""
            }
            writer.chapters.append(BKEpubPackageWriter.Chapter(title: BKMobiConverter.firstHeading(chapter)
                                                                   ?? (index == 0 ? writer.title : nil),
                                                               body: chapter))
        }

        let flat = ncx.compactMap { entry -> (entry: BKMobiConverter.NCXEntry, target: (chapter: Int, fragment: String?))? in
            guard let position = entry.position, let chapter = anchorChapter[position] else { return nil }
            return (entry, (chapter, "filepos\(position)"))
        }
        if !flat.isEmpty {
            writer.toc = BKMobiConverter.nest(flat)
        }
    }
}

// MARK: - KF8

private struct KF8 {
    let file: BKMobiFile
    let header: BKMobiFile.Header
    let text: Data

    struct Fragment {
        let insertPosition: Int
        let selector: String
        let length: Int
    }

    struct Part {
        var html: [UInt8]
        let start: Int
        var end: Int { start + html.count }
    }

    func build(into writer: inout BKEpubPackageWriter, resources: inout BKMobiConverter.Resources) throws {
        let flows = file.flows(text: text, header: header)
        guard let flow0 = flows.first.map(Array.init),
              let skeletonIndex = header.absolute(header.skeletonIndex),
              let fragmentIndex = header.absolute(header.fragmentIndex) else {
            throw BKBookError.unreadable("The KF8 book has no skeleton index")
        }
        let skeletons = file.index(at: skeletonIndex).entries
        let (fragmentEntries, selectors) = file.index(at: fragmentIndex)
        let fragments = fragmentEntries.map { entry in
            Fragment(insertPosition: Int(String(decoding: entry.text, as: UTF8.self)) ?? 0,
                     selector: entry.tags[2]?.first.flatMap { selectors[$0] }.map { String(decoding: $0, as: UTF8.self) } ?? "",
                     length: entry.tags[6].flatMap { $0.count >= 2 ? $0[1] : nil } ?? 0)
        }

        // Rebuild each part: its skeleton with its fragments inserted.
        var parts: [Part] = []
        var fragmentPointer = 0
        for skeleton in skeletons {
            guard let position = skeleton.tags[6], position.count >= 2,
                  position[0] + position[1] <= flow0.count else { continue }
            let skeletonStart = position[0]
            var base = skeletonStart + position[1]
            var html = Array(flow0[skeletonStart..<base])
            for _ in 0..<(skeleton.tags[1]?.first ?? 0) where fragmentPointer < fragments.count {
                let fragment = fragments[fragmentPointer]
                fragmentPointer += 1
                let end = min(base + fragment.length, flow0.count)
                let slice = flow0[min(base, end)..<end]
                let insert = min(max(0, fragment.insertPosition - skeletonStart), html.count)
                html.insert(contentsOf: slice, at: insert)
                base = end
            }
            parts.append(Part(html: html, start: skeletonStart))
        }
        guard !parts.isEmpty else { throw BKBookError.unreadable("The KF8 book has no parts") }

        // Resolve kindle:pos targets to an id in the part they point into.
        var linkedAids: [Int: Set<String>] = [:]
        func target(fid: Int, offset: Int) -> (part: Int, id: String?)? {
            guard fragments.indices.contains(fid) else { return nil }
            let position = fragments[fid].insertPosition + offset
            guard let partIndex = parts.firstIndex(where: { $0.start <= position && position < $0.end })
                    ?? parts.lastIndex(where: { $0.start <= position }) else { return nil }
            let id = Self.anchor(before: position - parts[partIndex].start, in: parts[partIndex].html)
            if let id, id.hasPrefix("aid-") { linkedAids[partIndex, default: []].insert(String(id.dropFirst(4))) }
            return (partIndex, id)
        }

        let ncx = BKMobiConverter.ncx(file: file, header: header)
        let flat = ncx.compactMap { entry -> (entry: BKMobiConverter.NCXEntry, target: (chapter: Int, fragment: String?))? in
            guard let fid = entry.fid, let resolved = target(fid: fid.0, offset: fid.1) else { return nil }
            return (entry, (resolved.part, resolved.id))
        }

        // Flows after the first: stylesheets and SVG images.
        var flowHrefs: [Int: String] = [:]
        for (index, flow) in flows.enumerated().dropFirst() {
            let isSVG = flow.prefix(200).range(of: Data("<svg".utf8)) != nil
            let href = isSVG ? String(format: "images/flow%04d.svg", index) : String(format: "styles/flow%04d.css", index)
            var content = String(decoding: flow, as: UTF8.self)
            content = Self.rewriteEmbeds(content, resources: &resources)
            writer.resources.append(.init(href: href, data: Data(content.utf8)))
            flowHrefs[index] = href
        }

        var titles: [Int: String] = [:]
        for item in flat where titles[item.target.chapter] == nil { titles[item.target.chapter] = item.entry.title }

        for (index, part) in parts.enumerated() {
            var html = String(decoding: part.html, as: UTF8.self)
            html = BKMobiConverter.replace(#"kindle:pos:fid:([0-9A-V]{4}):off:([0-9A-V]{10})"#, in: html) { groups in
                let fid = BKMobiConverter.base32(Substring(groups[1])), offset = BKMobiConverter.base32(Substring(groups[2]))
                guard let resolved = target(fid: fid, offset: offset) else { return "#" }
                let file = (writer.chapterHref(resolved.part) as NSString).lastPathComponent
                return file + (resolved.id.map { "#\($0)" } ?? "")
            }
            html = BKMobiConverter.replace(#"kindle:flow:([0-9A-V]{4})\?mime=[^"')\s]*"#, in: html) { groups in
                flowHrefs[BKMobiConverter.base32(Substring(groups[1]))].map { "../\($0)" } ?? ""
            }
            html = Self.rewriteEmbeds(html, resources: &resources)
            parts[index].html = Array(html.utf8)
        }
        // Elements linked by their aid get a matching id.
        for (index, aids) in linkedAids {
            var html = String(decoding: parts[index].html, as: UTF8.self)
            for aid in aids {
                if let range = html.range(of: "aid=\"\(aid)\"") ?? html.range(of: "aid='\(aid)'") {
                    html.replaceSubrange(range, with: "id=\"aid-\(aid)\" aid=\"\(aid)\"")
                }
            }
            parts[index].html = Array(html.utf8)
        }

        writer.chapters = parts.enumerated().map { index, part in
            let html = String(decoding: part.html, as: UTF8.self)
            return BKEpubPackageWriter.Chapter(title: titles[index] ?? BKMobiConverter.firstHeading(html)
                                                   ?? (index == 0 ? writer.title : nil),
                                               body: html, isFullDocument: true)
        }
        if !flat.isEmpty {
            writer.toc = BKMobiConverter.nest(flat)
        }
    }

    /// `kindle:embed:XXXX` → the resource's file, relative to `text/` or `styles/` (both one level down).
    static func rewriteEmbeds(_ content: String, resources: inout BKMobiConverter.Resources) -> String {
        BKMobiConverter.replace(#"kindle:embed:([0-9A-V]{4})(\?mime=[^"')\s]*)?"#, in: content) { groups in
            resources.href(forResource: BKMobiConverter.base32(Substring(groups[1]))).map { "../\($0)" } ?? ""
        }
    }

    /// The id (or `aid-` + aid) of the nearest element at or before `position` in a part, like
    /// KindleUnpack: links point at element positions, but files only have ids on some of them.
    static func anchor(before position: Int, in bytes: [UInt8]) -> String? {
        var cut = min(max(0, position), bytes.count)
        // Inside a tag: include the whole tag.
        if let close = bytes[cut...].firstIndex(of: UInt8(ascii: ">")) {
            let open = bytes[cut...].firstIndex(of: UInt8(ascii: "<")) ?? bytes.count
            if open == cut || close < open { cut = close + 1 }
        }
        let prefix = String(decoding: bytes[..<cut], as: UTF8.self)
        let tags = prefix.matches(of: #/<[^>]+>/#).map { String($0.output) }.reversed()
        for tag in tags {
            if tag.hasPrefix("<body") { return nil }
            if tag.hasPrefix("<meta") || tag.hasPrefix("</") { continue }
            if let match = tag.firstMatch(of: #/\s(?:id|name)\s*=\s*["']([^"']*)["']/#) { return String(match.1) }
            if let match = tag.firstMatch(of: #/\s(?:aid|AID)\s*=\s*["']([^"']+)["']/#) { return "aid-" + match.1 }
        }
        return nil
    }
}
