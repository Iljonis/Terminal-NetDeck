// swift-tools-version:6.2
// Terminal NetDeck: terminal nativo de macOS para ingenieros de red.
import PackageDescription

// Concurrencia de Swift 6.2 («approachable concurrency»): las funciones async sin actor corren en el de quien las
// llama (SE-0461) y los tipos @MainActor pueden cumplir protocolos sin actor sólo en el principal (SE-0470). Lo que
// deba ir fuera del principal (copias, MD5, edición remota) lleva `@concurrent`.
let concurrencia62: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "TerminalNetDeck",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TerminalNetDeck", targets: ["TerminalNetDeck"]),
        .library(name: "NetDeckCore", targets: ["NetDeckCore"]),
    ],
    dependencies: [
        // Emulador de terminal: vista AppKit + proceso local con pty (/usr/bin/ssh)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.3"),
    ],
    targets: [
        // Lógica sin interfaz: sesiones y saltos, Llavero y regla de usuario, Esc, pegado seguro, MultiExec, listas
        .target(name: "NetDeckCore", swiftSettings: concurrencia62),
        // La app (SwiftUI): todo en el hilo principal salvo lo que se marque nonisolated o @concurrent (SE-0466)
        .executableTarget(name: "TerminalNetDeck", dependencies: [
            "NetDeckCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
        ], swiftSettings: concurrencia62 + [.defaultIsolation(MainActor.self)]),
        // (y SwiftTerm sin vista, para leer el búfer como la pestaña: `BuferIncrementalTests`)
        .testTarget(name: "NetDeckCoreTests", dependencies: [
            "NetDeckCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
        ], swiftSettings: concurrencia62),
    ]
)
