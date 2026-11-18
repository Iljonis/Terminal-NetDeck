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

var products: [Product] = [
    .library(name: "NetDeckCore", targets: ["NetDeckCore"]),
]
var targets: [Target] = [
    // Lógica sin interfaz: sesiones y saltos, Llavero y regla de usuario, Esc, pegado seguro, MultiExec, listas
    .target(name: "NetDeckCore", dependencies: [
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows])),
    ], swiftSettings: concurrencia62),
    // (y SwiftTerm sin vista, para leer el búfer como la pestaña: `BuferIncrementalTests`)
    .testTarget(name: "NetDeckCoreTests", dependencies: [
        "NetDeckCore",
        .product(name: "SwiftTerm", package: "SwiftTerm", condition: .when(platforms: [.macOS, .linux])),
    ], swiftSettings: concurrencia62),
]
#if os(macOS)
products += [.executable(name: "TerminalNetDeck", targets: ["TerminalNetDeck"])]
// La app (SwiftUI): todo en el hilo principal salvo lo que se marque nonisolated o @concurrent (SE-0466)
targets += [.executableTarget(name: "TerminalNetDeck", dependencies: [
    "NetDeckCore",
    .product(name: "SwiftTerm", package: "SwiftTerm"),
], swiftSettings: concurrencia62 + [.defaultIsolation(MainActor.self)])]
#endif

let package = Package(
    name: "TerminalNetDeck",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: [
        // Emulador de terminal: vista AppKit + proceso local con pty (/usr/bin/ssh)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.3"),
        // CryptoKit compatible en Windows (en macOS se usa CryptoKit directamente)
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: targets
)
