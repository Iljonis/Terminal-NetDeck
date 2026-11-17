// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetDeckWindows",
    dependencies: [
        .package(name: "Terminal-NetDeck", path: "../.."),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3"),
        .package(url: "https://github.com/moreSwift/swift-winui.git", exact: "0.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "NetDeckWindows",
            dependencies: [
                .product(name: "NetDeckCore", package: "Terminal-NetDeck"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "WinUI", package: "swift-winui"),
            ],
            linkerSettings: [
                .linkedLibrary("WindowsFoundation"),
                .linkedLibrary("WinAppSDK"),
                .linkedLibrary("UWP"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
