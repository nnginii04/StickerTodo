// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickerTodo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StickerTodo",
            path: "Sources/StickerTodo"
        )
    ]
)
