// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BookKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macCatalyst(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BookKit",
            targets: ["BookKit"]
        )
    ],
    targets: [
        .target(
            name: "BookKitCore"
        ),
        .target(
            name: "BookKitParser",
            dependencies: ["BookKitCore"]
        ),
        .target(
            name: "BookKitRendering",
            dependencies: ["BookKitCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "BookKit",
            dependencies: [
                "BookKitCore",
                "BookKitParser",
                "BookKitRendering"
            ]
        ),
        .testTarget(
            name: "BookKitTests",
            dependencies: [
                "BookKitCore",
                "BookKitParser",
                "BookKitRendering"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
