// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mown",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        // Apple's cmark-gfm fork — the same package the Mown.xcodeproj
        // uses, so both build paths resolve the same source tree.
        .package(url: "https://github.com/apple/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .executableTarget(
            name: "Mown",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            // Reuse the §6 directory layout instead of moving sources under
            // SwiftPM's default Sources/Mown/.
            path: "Mown",
            // Resources are copied into the .app bundle by Scripts/build-app.sh
            // so PreviewTemplate.loadResource keeps using Bundle.main directly.
            // Info.plist is consumed by the bundling script, not SwiftPM.
            exclude: [
                "Info.plist",
                "Resources",
            ]
        ),
        .testTarget(
            name: "MownTests",
            dependencies: ["Mown"],
            path: "Tests"
        ),
    ]
)
