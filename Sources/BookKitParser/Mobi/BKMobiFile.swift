//
//  BKMobiFile.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Foundation
import BookKitCore

/// The container of Kindle books (MOBI and AZW3/KF8): a Palm database whose records hold the
/// headers, the compressed text, indexes and images. Only unencrypted books are readable.
struct BKMobiFile {

    /// One book inside the file: MOBI 6, or KF8. Combination files hold both; the KF8 one starts at
    /// `recordOffset` (see EXTH 121).
    struct Header {
        let recordOffset: Int
        let compression: Int
        let textRecordCount: Int
        let encryption: Int
        let version: Int
        let encoding: Int
        let firstImageIndex: Int
        let extraFlags: Int
        let fullName: String
        let exth: [Int: [Data]]
        let fdstIndex: Int
        let ncxIndex: Int
        let fragmentIndex: Int
        let skeletonIndex: Int

        var isKF8: Bool { version >= 8 }

        func exthString(_ type: Int) -> String? {
            exth[type]?.first.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func exthStrings(_ type: Int) -> [String] {
            (exth[type] ?? []).compactMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func exthInt(_ type: Int) -> Int? {
            guard let data = exth[type]?.first, data.count == 4 else { return nil }
            return Int(data.bigUInt32(at: 0))
        }

        /// Absolute record index of a header field that's relative to this book's record 0.
        func absolute(_ index: Int) -> Int? {
            index == 0xFFFF_FFFF ? nil : index + recordOffset
        }
    }

    private let data: Data
    private let recordOffsets: [Int]

    var recordCount: Int { recordOffsets.count }

    init(data: Data) throws {
        guard data.count >= 78 else { throw BKBookError.unreadable("Not a Kindle book") }
        let type = String(data: data.subdata(in: 60..<68), encoding: .ascii)
        guard type == "BOOKMOBI" else { throw BKBookError.unreadable("Not a Kindle book") }
        let count = Int(data.bigUInt16(at: 76))
        guard data.count >= 78 + count * 8 else { throw BKBookError.unreadable("Truncated Kindle book") }
        self.data = data
        recordOffsets = (0..<count).map { Int(data.bigUInt32(at: 78 + $0 * 8)) }
    }

    func record(_ index: Int) -> Data {
        guard recordOffsets.indices.contains(index) else { return Data() }
        let start = recordOffsets[index]
        let end = index + 1 < recordOffsets.count ? recordOffsets[index + 1] : data.count
        guard start <= end, end <= data.count else { return Data() }
        return data.subdata(in: start..<end)
    }

    // MARK: - Headers

    func header(at recordOffset: Int) throws -> Header {
        let r0 = record(recordOffset)
        guard r0.count >= 0x84, String(data: r0.subdata(in: 16..<20), encoding: .ascii) == "MOBI" else {
            throw BKBookError.unreadable("Missing MOBI header")
        }
        let headerLength = Int(r0.bigUInt32(at: 20))
        func field(_ offset: Int) -> Int {
            offset + 4 <= 16 + headerLength && offset + 4 <= r0.count ? Int(r0.bigUInt32(at: offset)) : 0xFFFF_FFFF
        }
        var exth: [Int: [Data]] = [:]
        if (r0.bigUInt32(at: 0x80) & 0x40) != 0 {
            var position = 16 + headerLength
            if position + 12 <= r0.count, String(data: r0.subdata(in: position..<(position + 4)), encoding: .ascii) == "EXTH" {
                let count = Int(r0.bigUInt32(at: position + 8))
                position += 12
                for _ in 0..<count where position + 8 <= r0.count {
                    let type = Int(r0.bigUInt32(at: position))
                    let length = Int(r0.bigUInt32(at: position + 4))
                    guard length >= 8, position + length <= r0.count else { break }
                    exth[type, default: []].append(r0.subdata(in: (position + 8)..<(position + length)))
                    position += length
                }
            }
        }
        let nameOffset = field(0x54), nameLength = field(0x58)
        let fullName = nameOffset + nameLength <= r0.count
            ? String(data: r0.subdata(in: nameOffset..<(nameOffset + nameLength)), encoding: .utf8) ?? ""
            : ""
        let extraFlags = headerLength >= 0xE4 && r0.count >= 0xF4 ? Int(r0.bigUInt16(at: 0xF2)) : 0
        return Header(recordOffset: recordOffset,
                      compression: Int(r0.bigUInt16(at: 0)),
                      textRecordCount: Int(r0.bigUInt16(at: 8)),
                      encryption: Int(r0.bigUInt16(at: 12)),
                      version: field(0x24),
                      encoding: field(0x1C),
                      firstImageIndex: field(0x6C),
                      extraFlags: extraFlags,
                      fullName: fullName,
                      exth: exth,
                      fdstIndex: field(0xC0),
                      ncxIndex: field(0xF4),
                      fragmentIndex: field(0xF8),
                      skeletonIndex: field(0xFC))
    }

    /// The book to read: the KF8 part of a combination file when there is one, else record 0's.
    func readableHeader() throws -> Header {
        let first = try header(at: 0)
        if !first.isKF8, let boundary = first.exthInt(121), boundary != 0xFFFF_FFFF, boundary < recordCount,
           let kf8 = try? header(at: boundary), kf8.isKF8 {
            return kf8
        }
        return first
    }

    // MARK: - Text

    /// The book's decompressed text (all flows, for KF8).
    func text(for header: Header) throws -> Data {
        guard header.encryption == 0 else { throw BKBookError.unreadable("This Kindle book is DRM-protected") }
        switch header.compression {
        case 1, 2: break
        case 17480: throw BKBookError.unreadable("HUFF/CDIC compressed Kindle books aren't supported")
        default: throw BKBookError.unreadable("Unknown Kindle compression \(header.compression)")
        }
        var text = Data()
        for index in 1...max(1, header.textRecordCount) {
            var record = self.record(header.recordOffset + index)
            let trailing = Self.trailingEntriesSize(record, flags: header.extraFlags)
            record = record.prefix(max(0, record.count - trailing))
            text.append(header.compression == 2 ? Self.palmDOCDecompress(record) : record)
        }
        return text
    }

    /// Size of the extra data at the end of a text record (multibyte overlap, indexing info).
    static func trailingEntriesSize(_ record: Data, flags: Int) -> Int {
        let bytes = [UInt8](record)
        var size = 0
        func entrySize(_ end: Int) -> Int {
            var result = 0, shift = 0, position = end
            while position > 0 {
                let byte = Int(bytes[position - 1])
                result |= (byte & 0x7F) << shift
                shift += 7
                position -= 1
                if byte & 0x80 != 0 || shift >= 28 { break }
            }
            return result
        }
        var test = flags >> 1
        while test != 0 {
            if test & 1 != 0 { size += entrySize(bytes.count - size) }
            test >>= 1
        }
        if flags & 1 != 0, bytes.count - size - 1 >= 0 {
            size += Int(bytes[bytes.count - size - 1] & 0x3) + 1
        }
        return min(size, bytes.count)
    }

    /// PalmDOC's LZ77 variant.
    static func palmDOCDecompress(_ input: Data) -> Data {
        let bytes = [UInt8](input)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count * 2)
        var position = 0
        while position < bytes.count {
            let c = Int(bytes[position])
            position += 1
            switch c {
            case 1...8:
                let end = min(position + c, bytes.count)
                output.append(contentsOf: bytes[position..<end])
                position = end
            case 0..<0x80:
                output.append(UInt8(c))
            case 0xC0...:
                output.append(0x20)
                output.append(UInt8(c ^ 0x80))
            default:
                guard position < bytes.count else { break }
                let pair = (c << 8) | Int(bytes[position])
                position += 1
                let distance = (pair >> 3) & 0x7FF
                let length = (pair & 7) + 3
                guard distance > 0, distance <= output.count else { continue }
                for _ in 0..<length {
                    output.append(output[output.count - distance])
                }
            }
        }
        return Data(output)
    }

    // MARK: - Indexes (INDX)

    struct IndexEntry {
        let text: Data
        let tags: [Int: [Int]]
    }

    /// The entries of the index starting at record `index`, and its CNCX strings by offset.
    func index(at index: Int) -> (entries: [IndexEntry], strings: [Int: Data]) {
        let headerRecord = record(index)
        guard let header = Self.indxHeader(headerRecord) else { return ([], [:]) }
        var strings: [Int: Data] = [:]
        for cncx in 0..<header.cncxCount {
            for (offset, string) in Self.cncxStrings(record(index + header.count + 1 + cncx)) {
                strings[offset + cncx * 0x10000] = string
            }
        }
        let (controlByteCount, tagTable) = Self.tagTable(headerRecord, at: header.length)
        var entries: [IndexEntry] = []
        for dataIndex in (index + 1)..<(index + 1 + header.count) {
            let indexRecord = record(dataIndex)
            guard let info = Self.indxHeader(indexRecord) else { continue }
            let bytes = [UInt8](indexRecord)
            var positions = (0..<info.count).compactMap { entry -> Int? in
                let offset = info.start + 4 + 2 * entry
                return offset + 2 <= bytes.count ? Int(indexRecord.bigUInt16(at: offset)) : nil
            }
            positions.append(info.start)
            for entry in 0..<(positions.count - 1) {
                let start = positions[entry], end = positions[entry + 1]
                guard start < bytes.count, start < end else { continue }
                let textLength = Int(bytes[start])
                guard start + 1 + textLength <= bytes.count else { continue }
                var text = Data(bytes[(start + 1)..<(start + 1 + textLength)])
                if let ordt = header.ordt2 {
                    text = Data(text.map { ordt.indices.contains(Int($0)) ? UInt8(truncatingIfNeeded: ordt[Int($0)]) : $0 })
                }
                let tags = Self.tagMap(bytes, controlByteCount: controlByteCount, table: tagTable,
                                       start: start + 1 + textLength, end: end)
                entries.append(IndexEntry(text: text, tags: tags))
            }
        }
        return (entries, strings)
    }

    private struct INDXHeader {
        let length: Int
        let start: Int
        let count: Int
        let cncxCount: Int
        let ordt2: [Int]?
    }

    private static func indxHeader(_ record: Data) -> INDXHeader? {
        guard record.count >= 56, String(data: record.prefix(4), encoding: .ascii) == "INDX" else { return nil }
        let word = { (n: Int) in Int(record.bigUInt32(at: 4 + 4 * n)) }
        var ordt2: [Int]?
        if record.count >= 0xA4 + 20 {
            let ocnt = Int(record.bigUInt32(at: 0xA4)), entries = Int(record.bigUInt32(at: 0xA8))
            let op2 = Int(record.bigUInt32(at: 0xB0))
            if (word(6) == 0xFDEA || ocnt != 0 || entries > 0), op2 + 4 + entries * 2 <= record.count,
               String(data: record.subdata(in: op2..<(op2 + 4)), encoding: .ascii) == "ORDT" {
                ordt2 = (0..<entries).map { Int(record.bigUInt16(at: op2 + 4 + 2 * $0)) }
            }
        }
        return INDXHeader(length: word(0), start: word(4), count: word(5), cncxCount: word(12), ordt2: ordt2)
    }

    private static func tagTable(_ record: Data, at start: Int) -> (Int, [(tag: Int, perEntry: Int, mask: Int, end: Bool)]) {
        guard start + 12 <= record.count, String(data: record.subdata(in: start..<(start + 4)), encoding: .ascii) == "TAGX" else {
            return (0, [])
        }
        let firstEntry = Int(record.bigUInt32(at: start + 4))
        let controlBytes = Int(record.bigUInt32(at: start + 8))
        let bytes = [UInt8](record)
        var table: [(Int, Int, Int, Bool)] = []
        var position = start + 12
        while position + 4 <= start + firstEntry, position + 4 <= bytes.count {
            table.append((Int(bytes[position]), Int(bytes[position + 1]), Int(bytes[position + 2]), bytes[position + 3] == 1))
            position += 4
        }
        return (controlBytes, table)
    }

    private static func tagMap(_ bytes: [UInt8], controlByteCount: Int,
                               table: [(tag: Int, perEntry: Int, mask: Int, end: Bool)],
                               start: Int, end: Int) -> [Int: [Int]] {
        var controlIndex = 0
        var dataStart = start + controlByteCount
        var found: [(tag: Int, count: Int?, byteLength: Int?, perEntry: Int)] = []
        for entry in table {
            if entry.end {
                controlIndex += 1
                continue
            }
            guard start + controlIndex < bytes.count else { break }
            var value = Int(bytes[start + controlIndex]) & entry.mask
            guard value != 0 else { continue }
            if value == entry.mask {
                if entry.mask.nonzeroBitCount > 1 {
                    let (consumed, length) = variableWidthValue(bytes, at: dataStart)
                    dataStart += consumed
                    found.append((entry.tag, nil, length, entry.perEntry))
                } else {
                    found.append((entry.tag, 1, nil, entry.perEntry))
                }
            } else {
                var mask = entry.mask
                while mask & 1 == 0 { mask >>= 1; value >>= 1 }
                found.append((entry.tag, value, nil, entry.perEntry))
            }
        }
        var tags: [Int: [Int]] = [:]
        for item in found {
            var values: [Int] = []
            if let count = item.count {
                for _ in 0..<(count * item.perEntry) where dataStart < end {
                    let (consumed, value) = variableWidthValue(bytes, at: dataStart)
                    dataStart += consumed
                    values.append(value)
                }
            } else if let byteLength = item.byteLength {
                var total = 0
                while total < byteLength, dataStart < end {
                    let (consumed, value) = variableWidthValue(bytes, at: dataStart)
                    dataStart += consumed
                    total += consumed
                    values.append(value)
                }
            }
            tags[item.tag] = values
        }
        return tags
    }

    /// Forward variable-width integer: 7 bits per byte, the last byte has the high bit set.
    static func variableWidthValue(_ bytes: [UInt8], at offset: Int) -> (consumed: Int, value: Int) {
        var value = 0, consumed = 0
        while offset + consumed < bytes.count {
            let byte = Int(bytes[offset + consumed])
            consumed += 1
            value = (value << 7) | (byte & 0x7F)
            if byte & 0x80 != 0 { break }
        }
        return (max(consumed, 1), value)
    }

    private static func cncxStrings(_ record: Data) -> [Int: Data] {
        let bytes = [UInt8](record)
        var strings: [Int: Data] = [:]
        var offset = 0
        while offset < bytes.count, bytes[offset] != 0 {
            let start = offset
            let (consumed, length) = variableWidthValue(bytes, at: offset)
            offset += consumed
            guard offset + length <= bytes.count else { break }
            strings[start] = Data(bytes[offset..<(offset + length)])
            offset += length
        }
        return strings
    }

    // MARK: - KF8 flows

    /// The text split into flows by the FDST record (flow 0 is the HTML; others are CSS or SVG).
    func flows(text: Data, header: Header) -> [Data] {
        guard let fdst = header.absolute(header.fdstIndex) else { return [text] }
        let record = self.record(fdst)
        guard record.count >= 12, String(data: record.prefix(4), encoding: .ascii) == "FDST" else { return [text] }
        let count = Int(record.bigUInt32(at: 8))
        var flows: [Data] = []
        for index in 0..<count where 12 + index * 8 + 8 <= record.count {
            let start = Int(record.bigUInt32(at: 12 + index * 8)), end = Int(record.bigUInt32(at: 16 + index * 8))
            guard start <= end, end <= text.count else { continue }
            flows.append(text.subdata(in: start..<end))
        }
        return flows.isEmpty ? [text] : flows
    }
}

extension Data {
    func bigUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) << 8 | UInt16(self[startIndex + offset + 1])
    }

    func bigUInt32(at offset: Int) -> UInt32 {
        UInt32(bigUInt16(at: offset)) << 16 | UInt32(bigUInt16(at: offset + 2))
    }
}
