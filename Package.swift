// swift-tools-version:6.0
// Terminal NetDeck: terminal nativo de macOS para ingenieros de red.
import PackageDescription

let package = Package(
    name: "TerminalNetDeck",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TerminalNetDeck", targets: ["TerminalNetDeck"]),
        .library(name: "NetDeckCore", targets: ["NetDeckCore"]),
    ],
    dependencies: [
        // Emulador de terminal: vista AppKit + proceso local con pty (/usr/bin/ssh)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.0"),
    ],
    targets: [
        // Lógica sin interfaz: sesiones y saltos, Llavero y regla de usuario, Esc, pegado seguro, MultiExec, listas
        .target(name: "NetDeckCore"),
        // La app (SwiftUI)
        .executableTarget(name: "TerminalNetDeck", dependencies: [
            "NetDeckCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
        ]),
        .testTarget(name: "NetDeckCoreTests", dependencies: ["NetDeckCore"]),
    ]
)
