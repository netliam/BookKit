//
//  BKPDFLocation.swift
//  BookKit
//
//  Created by Liam Smith-Gales on 16/11/26.
//

import CoreGraphics
import Foundation

/// Where a PDF highlight, bookmark or reading position is: a page, and for highlights the
/// selected lines' rectangles in PDF page space. Stored in `BKHighlight.coords` and
/// `BKReadingPosition.coords` as `pdf|<page>|x,y,w,h;x,y,w,h`.
public struct BKPDFLocation: Equatable, Sendable {
    /// Zero-based page index.
    public var pageIndex: Int
    /// Line rectangles in page space (origin at the bottom left); empty for a whole page.
    public var rects: [CGRect]

    public init(pageIndex: Int, rects: [CGRect] = []) {
        self.pageIndex = pageIndex
        self.rects = rects
    }

    private static let prefix = "pdf"

    public var coords: String {
        let rectList = rects.map { rect in
            [rect.origin.x, rect.origin.y, rect.width, rect.height]
                .map { String(format: "%.2f", Double($0)) }
                .joined(separator: ",")
        }.joined(separator: ";")
        return "\(Self.prefix)|\(pageIndex)|\(rectList)"
    }

    /// Reads `coords`; `nil` when they aren't PDF coords (e.g. an EPUB highlight's).
    public init?(coords: String) {
        let parts = coords.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Self.prefix, let page = Int(parts[1]), page >= 0 else { return nil }
        var rects: [CGRect] = []
        for rect in parts[2].split(separator: ";") {
            let values = rect.split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { return nil }
            rects.append(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
        }
        self.init(pageIndex: page, rects: rects)
    }

    /// The rectangle around all the lines.
    public var bounds: CGRect {
        rects.reduce(CGRect.null) { $0.union($1) }
    }
}
