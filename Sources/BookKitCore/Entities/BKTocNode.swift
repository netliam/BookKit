//
//  BKTocNode.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

public struct BKTocNode: Sendable {
    public let label: String
    public let href: String?
    public var children: [BKTocNode]

    public init(label: String, href: String?, children: [BKTocNode]) {
        self.label = label
        self.href = href
        self.children = children
    }

    static let mock: BKTocNode = BKTocNode(label: "BKTocNode", href: "", children: [.mock])
}
