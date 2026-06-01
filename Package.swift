// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Inkwell",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        // Apple's cmark-gfm fork — the same package the Inkwell.xcodeproj
        // uses, so both build paths resolve the same source tree.
        .package(url: "https://github.com/apple/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .executableTarget(
            name: "Inkwell",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            // Reuse the §6 directory layout instead of moving sources under
            // SwiftPM's default Sources/Inkwell/.
            path: "Inkwell",
            // Resources are copied into the .app bundle by Scripts/build-app.sh
            // so PreviewTemplate.loadResource keeps using Bundle.main directly.
            // Info.plist is consumed by the bundling script, not SwiftPM.
            exclude: [
                "Info.plist",
                "Resources",
            ]
        ),
        .testTarget(
            name: "InkwellTests",
            dependencies: ["Inkwell"],
            path: "Tests"
        ),
    ]
)
