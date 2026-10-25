// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zhuguang",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Zhuguang", targets: ["Zhuguang"])
    ],
    targets: [
        .executableTarget(name: "Zhuguang")
    ]
)
