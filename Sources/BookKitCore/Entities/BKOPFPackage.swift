//
//  BKOPFPackage.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import Foundation

public struct BKOPFPackage {
    public let opfURL: URL
    public var metadata: BKOPFMetadata
    public var manifest: [BKManifestItem]
    public var spine: [BKSpineItem]
    public var guide: [BKGuideRef]
    /// The CFI step of `<spine>` inside `<package>`: 2 × its position among the package's child
    /// elements (6 when it's the third, as in most books).
    public var spineStep: Int

    public init(opfURL: URL,
                metadata: BKOPFMetadata,
                manifest: [BKManifestItem],
                spine: [BKSpineItem],
                guide: [BKGuideRef],
                spineStep: Int = 6) {
        self.opfURL = opfURL
        self.metadata = metadata
        self.manifest = manifest
        self.spine = spine
        self.guide = guide
        self.spineStep = spineStep
    }
}
