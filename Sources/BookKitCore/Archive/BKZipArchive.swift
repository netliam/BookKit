//
//  BKZipArchive.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import Compression
import Foundation

/// Reads files out of a ZIP archive (comic books, EPUBs) without extracting it: entries are read
/// on demand, so large archives don't need to fit in memory. Stored and deflated entries are
/// supported, which covers CBZ and EPUB files; ZIP64 archives (over 4 GB) aren't.
public final class BKZipArchive: @unchecked Sendable {

    public struct Entry: Sendable, Equatable {
        public let path: String
        public let uncompressedSize: Int
        fileprivate let compressedSize: Int
        fileprivate let method: UInt16
        fileprivate let localHeaderOffset: Int

        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    public enum ArchiveError: Error, Equatable {
        case notAZipFile
        case unsupported(String)
        case corrupt(String)
        case missingEntry(String)
    }

    public let url: URL
    /// Every entry, in archive order.
    public let entries: [Entry]

    private let handle: FileHandle
    /// Reads share one file handle, so they take turns.
    private let lock = NSLock()

    public init(url: URL) throws {
        self.url = url
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ArchiveError.notAZipFile
        }
        entries = try Self.readCentralDirectory(handle)
    }

    deinit {
        try? handle.close()
    }

    public func entry(at path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    /// The uncompressed contents of `entry`.
    public func data(for entry: Entry) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        // The local header repeats the name and may have a different extra field length.
        let header = try read(at: entry.localHeaderOffset, count: 30)
        guard header.uint32(at: 0) == 0x0403_4B50 else { throw ArchiveError.corrupt("Bad local header for \(entry.path)") }
        let dataOffset = entry.localHeaderOffset + 30 + Int(header.uint16(at: 26)) + Int(header.uint16(at: 28))
        let compressed = try read(at: dataOffset, count: entry.compressedSize)

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ArchiveError.unsupported("Compression method \(entry.method) (\(entry.path))")
        }
    }

    public func data(at path: String) throws -> Data {
        guard let entry = entry(at: path) else { throw ArchiveError.missingEntry(path) }
        return try data(for: entry)
    }

    /// Writes every file of the archive under `directory`, refusing paths that would leave it.
    public func extractAll(to directory: URL) throws {
        let root = directory.standardizedFileURL
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in entries where !entry.isDirectory {
            let destination = root.appendingPathComponent(entry.path).standardizedFileURL
            guard destination.path.hasPrefix(root.path + "/") else {
                throw ArchiveError.corrupt("Entry outside the archive folder: \(entry.path)")
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data(for: entry).write(to: destination)
        }
    }

    // MARK: - Reading

    private func read(at offset: Int, count: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw ArchiveError.corrupt("Unexpected end of file") }
        return data
    }

    private static func readCentralDirectory(_ handle: FileHandle) throws -> [Entry] {
        let fileSize = Int(try handle.seekToEnd())
        guard fileSize >= 22 else { throw ArchiveError.notAZipFile }
        // The end-of-central-directory record is in the last 22 bytes plus a comment of up to 64 KB.
        let tailLength = min(fileSize, 22 + 0xFFFF)
        try handle.seek(toOffset: UInt64(fileSize - tailLength))
        let tail = try handle.read(upToCount: tailLength) ?? Data()
        guard let eocd = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.uint32(at: $0) == 0x0605_4B50 }) else {
            throw ArchiveError.notAZipFile
        }
        let count = Int(tail.uint16(at: eocd + 10))
        let size = Int(tail.uint32(at: eocd + 12))
        let offset = Int(tail.uint32(at: eocd + 16))
        guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else {
            throw ArchiveError.unsupported("ZIP64 archives")
        }
        guard offset + size <= fileSize else { throw ArchiveError.corrupt("Central directory out of range") }
        try handle.seek(toOffset: UInt64(offset))
        let directory = try handle.read(upToCount: size) ?? Data()

        var entries: [Entry] = []
        var position = 0
        for _ in 0..<count {
            guard position + 46 <= directory.count, directory.uint32(at: position) == 0x0201_4B50 else {
                throw ArchiveError.corrupt("Bad central directory entry")
            }
            let flags = directory.uint16(at: position + 8)
            let nameLength = Int(directory.uint16(at: position + 28))
            let extraLength = Int(directory.uint16(at: position + 30))
            let commentLength = Int(directory.uint16(at: position + 32))
            guard position + 46 + nameLength <= directory.count else { throw ArchiveError.corrupt("Bad entry name") }
            let nameData = directory.subdata(in: (position + 46)..<(position + 46 + nameLength))
            // Bit 11: UTF-8 names. Older archives use CP437; Latin-1 keeps ASCII names right.
            let name = (flags & 0x0800) != 0
                ? String(decoding: nameData, as: UTF8.self)
                : (String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "")
            if (flags & 0x0001) != 0 {
                throw ArchiveError.unsupported("Encrypted archives")
            }
            entries.append(Entry(path: name,
                                 uncompressedSize: Int(directory.uint32(at: position + 24)),
                                 compressedSize: Int(directory.uint32(at: position + 20)),
                                 method: directory.uint16(at: position + 10),
                                 localHeaderOffset: Int(directory.uint32(at: position + 42))))
            position += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Inflates raw DEFLATE data (ZIP stores it without a zlib header, which is what
    /// `COMPRESSION_ZLIB` expects).
    static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, expectedSize, sourceBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ArchiveError.corrupt("Couldn't inflate entry") }
        return output
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }
}
