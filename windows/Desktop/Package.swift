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
            name: "NetDeckAskpass",
            dependencies: [.product(name: "NetDeckCore", package: "Terminal-NetDeck")]
        ),
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
                // App gráfica, sin ventana de consola detrás. Con -Xlinker: suelto, clang tomaba «/SUBSYSTEM…» por
                // una ruta. Swift genera `main`, no `WinMain`: de ahí el punto de entrada.
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
