// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Recorte",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Recorte", path: "Sources/Recorte")
    ]
)
