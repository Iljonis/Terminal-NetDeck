// swift-tools-version:6.0
// Terminal NetDeck (provisional): app nativa de macOS que sustituirá a NetDeck (bash + tmux).
import PackageDescription

let package = Package(
    name: "TerminalNetDeck",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "NetDeckProvisional", targets: ["NetDeckProvisional"]),
        .library(name: "NetDeckCore", targets: ["NetDeckCore"]),
    ],
    dependencies: [
        // Emulador de terminal: vista AppKit + proceso local con pty (/usr/bin/ssh)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.0"),
        // SSH nativo (fase 2: canales propios por pestaña, sin /usr/bin/ssh)
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.104.0"),
    ],
    targets: [
        // Lógica sin interfaz: sesiones y saltos, Llavero y regla de usuario, Esc, pegado seguro, MultiExec, listas
        .target(name: "NetDeckCore"),
        // Transporte SSH nativo (esqueleto)
        .target(name: "NetDeckSSH", dependencies: [
            "NetDeckCore",
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIOCore", package: "swift-nio"),
        ]),
        // La app (SwiftUI)
        .executableTarget(name: "NetDeckProvisional", dependencies: [
            "NetDeckCore",
            "NetDeckSSH",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
        ]),
        .testTarget(name: "NetDeckCoreTests", dependencies: ["NetDeckCore"]),
    ]
)
