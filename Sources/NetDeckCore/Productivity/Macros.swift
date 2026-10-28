import Foundation

// Macros: órdenes grabadas o escritas a mano que se reproducen con las mismas protecciones que el pegado seguro
// (se paran ante un error del equipo, un paginador, una petición de contraseña/OTP o una orden peligrosa sin
// confirmar; Esc/Ctrl+C las cortan). Nunca llevan secretos: no se graba lo tecleado en una petición de contraseña,
// passphrase u OTP, ni lo que escribe la app desde el Llavero (eso no pasa por el teclado). Sólo se reproducen por
// una acción del usuario: cargarlas (al arrancar, importar o restaurar) no ejecuta nada.

/// Un paso: enviar una línea, esperar al prompt, esperar un texto (regex acotada) o una pausa.
public struct MacroStep: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case send = "enviar", prompt, text = "texto", pause = "pausa"
    }

    /// (sólo para las listas de la interfaz; no se guarda)
    public var id = UUID()
    public var kind: Kind
    /// La línea (enviar) o la regex (texto); vacío en los demás.
    public var text: String
    /// Timeout de las esperas o duración de la pausa, en segundos.
    public var seconds: Double

    public static let defaultTimeout = 20.0
    public static let maxTimeout = 600.0
    public static let maxPause = 60.0
    public static let maxLine = 1000

    public init(kind: Kind, text: String = "", seconds: Double = MacroStep.defaultTimeout) {
        self.kind = kind
        self.text = text
        self.seconds = seconds
    }

    public static func send(_ line: String) -> Self { .init(kind: .send, text: line, seconds: 0) }
    public static func prompt(timeout: Double = defaultTimeout) -> Self { .init(kind: .prompt, seconds: timeout) }
    public static func text(_ regex: String, timeout: Double = defaultTimeout) -> Self { .init(kind: .text, text: regex, seconds: timeout) }
    public static func pause(_ seconds: Double) -> Self { .init(kind: .pause, seconds: seconds) }

    enum CodingKeys: String, CodingKey { case kind = "tipo", text = "texto", seconds = "segundos" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? (kind == .pause ? 1 : Self.defaultTimeout)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        if kind == .send || kind == .text { try c.encode(text, forKey: .text) }
        if kind != .send { try c.encode(seconds, forKey: .seconds) }
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.kind == b.kind && a.text == b.text && (a.kind == .send || a.seconds == b.seconds)
    }
    public func hash(into h: inout Hasher) { h.combine(kind); h.combine(text) }

    /// Por qué no vale (para el usuario), o nil.
    public var problem: String? {
        switch kind {
        case .send:
            if text.trimmed.isEmpty { return L("línea vacía") }
            if text.count > Self.maxLine { return L("más de \(String(Self.maxLine)) caracteres") }
            if SessionFile.hasControl(text) { return L("saltos de línea o caracteres de control") }
        case .prompt:
            if !(1...Self.maxTimeout).contains(seconds) { return L("el tiempo de espera va de 1 a \(String(Int(Self.maxTimeout))) s") }
        case .text:
            if let p = PromptRule.problem(text) { return p }
            if !(1...Self.maxTimeout).contains(seconds) { return L("el tiempo de espera va de 1 a \(String(Int(Self.maxTimeout))) s") }
        case .pause:
            if !(0.1...Self.maxPause).contains(seconds) { return L("la pausa va de 0,1 a \(String(Int(Self.maxPause))) s") }
        }
        return nil
    }
}

/// Una macro: nombre, pasos y si hay que confirmar antes de reproducirla.
public struct Macro: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var confirm: Bool
    public var steps: [MacroStep]

    public static let maxName = 80
    public static let maxSteps = 500

    public init(id: UUID = UUID(), name: String, confirm: Bool = false, steps: [MacroStep] = []) {
        self.id = id
        self.name = name
        self.confirm = confirm
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey { case id, name = "nombre", confirm = "confirmar", steps = "pasos" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        confirm = try c.decodeIfPresent(Bool.self, forKey: .confirm) ?? false
        steps = try c.decode([MacroStep].self, forKey: .steps)
    }

    /// Las líneas que envía.
    public var lines: [String] { steps.filter { $0.kind == .send }.map(\.text) }
    /// Las peligrosas (para confirmarlas ANTES de empezar).
    public var dangerousLines: [String] { lines.filter(PasteRules.dangerous.matches) }

    /// Por qué no vale (con el paso), o nil.
    public var problem: String? {
        let n = name.trimmed
        if n.isEmpty { return L("sin nombre") }
        if n.count > Self.maxName { return L("nombre de más de \(String(Self.maxName)) caracteres") }
        if SessionFile.hasControl(n) { return L("el nombre lleva caracteres de control") }
        if steps.isEmpty { return L("sin pasos") }
        if steps.count > Self.maxSteps { return L("más de \(String(Self.maxSteps)) pasos") }
        if !steps.contains(where: { $0.kind == .send }) { return L("no envía ninguna orden") }
        for (i, s) in steps.enumerated() {
            if let p = s.problem { return L("paso \(String(i + 1)): \(p)") }
        }
        return nil
    }

    /// Las líneas grabadas, cada una seguida de «esperar prompt».
    public static func recorded(_ lines: [String], timeout: Double = MacroStep.defaultTimeout) -> [MacroStep] {
        lines.flatMap { [MacroStep.send($0), .prompt(timeout: timeout)] }
    }
}

/// Las macros guardadas: `AppPaths.support/macros.json` (0600, con copia antes de sustituirlo), versionado.
/// Leerlas no ejecuta nada ni escribe nada.
public struct MacroLibrary: Sendable, Equatable {
    public static let version = 1
    public var macros: [Macro]

    public static var defaultURL: URL { AppPaths.support.appendingPathComponent("macros.json") }

    public init(macros: [Macro] = []) { self.macros = macros }

    /// Lo leído: las macros válidas, avisos de las que se han ignorado y, si el archivo no se puede usar (ilegible,
    /// JSON roto o versión desconocida), el error: entonces no se toca y, al guardar, se aparta a `.ilegible`.
    public struct Loaded: Sendable {
        public var library: MacroLibrary
        public var warnings: [String]
        public var error: String?
    }

    private struct File: Decodable {
        var version: Int
        var macros: [Lenient]
        enum CodingKeys: String, CodingKey { case version, macros }
    }

    /// Una entrada que no se entiende no tira las demás.
    private struct Lenient: Decodable {
        var macro: Macro?
        init(from decoder: Decoder) throws { macro = try? Macro(from: decoder) }
    }

    private struct Header: Decodable { var version: Int }

    public static func load(from url: URL = defaultURL) -> Loaded {
        let path = AppPaths.tilde(url.path)
        let text: String
        do {
            guard let t = try SafeFile.read(url) else { return Loaded(library: .init(), warnings: [], error: nil) }
            text = t
        } catch {
            return Loaded(library: .init(), warnings: [], error: error.localizedDescription)
        }
        let data = Data(text.utf8)
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            return Loaded(library: .init(), warnings: [], error: L("\(path) no se entiende (JSON roto): no lo sobrescribo hasta que guardes; entonces queda aparte en macros.json.ilegible"))
        }
        guard header.version == version else {
            return Loaded(library: .init(), warnings: [], error: L("\(path) es de otra versión (\(String(header.version))): no lo sobrescribo hasta que guardes; entonces queda aparte en macros.json.ilegible"))
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            return Loaded(library: .init(), warnings: [], error: L("\(path) no se entiende (JSON roto): no lo sobrescribo hasta que guardes; entonces queda aparte en macros.json.ilegible"))
        }
        var lib = MacroLibrary(), warnings: [String] = []
        for (i, entry) in file.macros.enumerated() {
            guard let m = entry.macro else { warnings.append(L("macro \(String(i + 1)): no se entiende; se ignora")); continue }
            if let p = m.problem { warnings.append(L("«\(m.name)»: \(p); se ignora")); continue }
            if lib.macros.contains(where: { $0.name.lowercased() == m.name.trimmed.lowercased() || $0.id == m.id }) {
                warnings.append(L("«\(m.name)»: repetida; se ignora"))
                continue
            }
            var ok = m
            ok.name = m.name.trimmed
            lib.macros.append(ok)
        }
        return Loaded(library: lib, warnings: warnings, error: nil)
    }

    public enum SaveError: LocalizedError, Equatable {
        case invalid(String, String)
        case duplicate(String)
        case duplicateID(String)
        public var errorDescription: String? {
            switch self {
            case .invalid(let n, let p): L("«\(n)»: \(p)")
            case .duplicate(let n): L("Hay dos macros con el nombre «\(n)»")
            case .duplicateID(let n): L("Hay dos macros con el mismo identificador («\(n)»)")
            }
        }
    }

    /// Por qué no se puede guardar, o nil.
    public var problem: SaveError? {
        var seen = Set<String>(), ids = Set<UUID>()
        for m in macros {
            if let p = m.problem { return .invalid(m.name, p) }
            if !seen.insert(m.name.trimmed.lowercased()).inserted { return .duplicate(m.name.trimmed) }
            if !ids.insert(m.id).inserted { return .duplicateID(m.name.trimmed) }
        }
        return nil
    }

    /// Guarda (validadas). `setAsideUnusable`: el archivo de ahora no se pudo usar al leerlo; antes de escribir se
    /// aparta a `macros.json.ilegible` (no se pierde).
    public func save(to url: URL = MacroLibrary.defaultURL, setAsideUnusable: Bool = false) throws {
        try save(to: url, setAsideUnusable: setAsideUnusable, write: { try SafeFile.write($0, to: $1) })
    }

    // (la escritura se puede sustituir en las pruebas para comprobar la vuelta atrás sin depender de permisos)
    func save(to url: URL, setAsideUnusable: Bool, write: (String, URL) throws -> Void) throws {
        if let p = problem { throw p }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        struct Out: Encodable { var version: Int; var macros: [Macro] }
        let out = Out(version: Self.version, macros: macros.map { var m = $0; m.name = m.name.trimmed; return m })
        let text = String(decoding: try enc.encode(out), as: UTF8.self) + "\n"
        AppPaths.ensure(url.deletingLastPathComponent())
        let fm = FileManager.default
        guard setAsideUnusable, fm.fileExists(atPath: url.path) else {
            try SafeFile.backup(url)
            try write(text, url)
            return
        }
        // (el ilegible se aparta con un nombre único; la copia .ilegible anterior sólo se sustituye tras escribir el
        // nuevo, y si la escritura falla, el original vuelve a su sitio: nunca se queda sin ninguno)
        let aside = url.appendingPathExtension("ilegible")
        let held = url.appendingPathExtension("ilegible-\(UUID().uuidString)")
        try fm.moveItem(at: url, to: held)
        do {
            try write(text, url)
            if fm.fileExists(atPath: aside.path) { _ = try fm.replaceItemAt(aside, withItemAt: held) }
            else { try fm.moveItem(at: held, to: aside) }
        } catch {
            if fm.fileExists(atPath: held.path) {
                if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: held) }
                else { try fm.moveItem(at: held, to: url) }
            }
            throw error
        }
    }

    public func macro(_ id: Macro.ID?) -> Macro? { macros.first { $0.id == id } }

    /// «base», «base 2», «base 3»… (sin repetir, sin mirar mayúsculas), sin contar la de `except`.
    public func uniqueName(_ base: String, except: Macro.ID? = nil) -> String {
        let b = base.trimmed.isEmpty ? "macro" : String(base.trimmed.prefix(Macro.maxName - 4))
        let taken = Set(macros.filter { $0.id != except }.map { $0.name.trimmed.lowercased() })
        var n = b, k = 2
        while taken.contains(n.lowercased()) { n = "\(b) \(k)"; k += 1 }
        return n
    }
}

// MARK: - grabar

/// Graba las LÍNEAS que el usuario envía con Intro en una pestaña (no las teclas sueltas). Sólo recibe lo tecleado o
/// pegado por el usuario (`AppModel.userInput`): lo que escribe la app (contraseñas del Llavero, askpass, botones,
/// pegado seguro) va directo al proceso y aquí no llega. Además nunca graba una línea empezada o terminada mientras
/// la línea del cursor pide un secreto (contraseña, passphrase, OTP…) ni mientras la pestaña se autentica.
@MainActor
public final class MacroRecorder {
    public private(set) var lines: [String] = []
    /// Líneas no grabadas por ser un secreto (o no poder leerse).
    public private(set) var skipped = 0
    /// Por qué se descartó la última (para el registro de depuración; nunca lleva lo tecleado): «enmascarada-secreto»,
    /// «autenticando», «sin-prompt», «misma-fila», «sin-prefijo» o «no-conexion».
    public private(set) var lastDrop: String?
    /// ¿Se está autenticando? (la app añade «aún no ha llegado a su primer prompt», como MultiExec)
    public var awaitingAuth: (any TerminalIO) -> Bool = { SecretPrompt.asks($0.cursorLine) }
    /// Recupera la línea que la persona elige con flechas/Tab, anclada al prompt donde empezó a editar.
    private let allowScreenFallback: Bool
    private let soloConexiones: Bool
    private var historial = false

    private var buffer: [UInt8] = []
    /// Sólo caracteres y borrar: el búfer es exactamente lo enviado. Con flechas, Tab… se lee de la pantalla.
    private var clean = true
    /// La línea del cursor antes de la primera tecla (el prompt).
    private var start: String?
    /// La línea es un secreto (contraseña, OTP…) o no se puede comprobar: no se graba (`maskedBy`: el motivo).
    private var masked = false { didSet { if !masked { maskedBy = nil } } }
    private var maskedBy: String?
    /// Ya se ha mirado la pantalla con la primera tecla que cambia la línea.
    private var checked = false
    /// La fila del cursor en el último Intro con algo escrito. Lo siguiente sólo se graba si el equipo ya ha contestado
    /// (el cursor está en otra fila y en ella hay un prompt): si no, puede ser la respuesta a un «Password:» que aún no
    /// ha pintado (un pegado «enable⏎contraseña⏎», entero o llegue en los trozos que llegue). La fila es absoluta
    /// (`BufferRows`): con el historial lleno también avanza. Que salga algo (un BEL, un color) no prueba que haya
    /// contestado: sólo la fila. `realigned`: el búfer se ha recolocado y la fila de entonces ya no se puede comparar.
    private var lastEnterRow: Int?
    private var lastEnterAt: Date?
    private var realigned = false
    /// El reloj de esa marca (las pruebas ponen el suyo).
    public var now: () -> Date = Date.init
    /// Una recolocación sólo enmascara lo que llega en este tiempo tras el Intro (un pegado troceado).
    static let realignWindow: TimeInterval = 2
    private var justEntered: Bool { lastEnterAt.map { now().timeIntervalSince($0) < Self.realignWindow } ?? false }
    private enum Escape { case none, started, csi([UInt8]), ss3 }
    private var escape = Escape.none

    public init(allowScreenFallback: Bool = true, soloConexiones: Bool = false) {
        self.allowScreenFallback = allowScreenFallback
        self.soloConexiones = soloConexiones
    }

    public func feed(_ bytes: [UInt8], from io: TerminalIO) {
        for b in bytes {
            if start == nil { start = io.cursorLine }
            // (al empezar y con cada tecla: un «Password:» que sale a mitad también cuenta)
            if SecretPrompt.asks(io.cursorLine) { mask("enmascarada-secreto") } else if awaitingAuth(io) { mask("autenticando") }
            switch escape {
            case .started:
                escape = b == 0x5B ? .csi([]) : (b == 0x4F ? .ss3 : .none)
                if b != 0x5B { check(io); clean = false }
                // (Esc suelto y luego una tecla, o Alt+tecla: esa tecla no se pierde; la línea se lee de la pantalla. Un
                // Esc al final de un trozo sigue a la espera: los marcadores del pegado pueden llegar partidos)
                if b == 0x5B || b == 0x4F { continue }
            case .ss3:
                escape = .none
                if b == 0x41 || b == 0x42 { historial = true }
                check(io)
                clean = false
                continue
            case .csi(var params):
                if (0x40...0x7E).contains(b) {
                    if b == 0x41 || b == 0x42 { historial = true }
                    // (pegado entre corchetes: ESC[200~ … ESC[201~ no cambia la línea)
                    if b != 0x7E || !["200", "201"].contains(String(decoding: params, as: UTF8.self)) { check(io); clean = false }
                    escape = .none
                } else {
                    params.append(b)
                    escape = .csi(params)
                }
                continue
            case .none: break
            }
            switch b {
            case 13, 10: finish(io)
            case 3: reset()                                       // Ctrl+C: la línea no se envía
            case 0x15: buffer = []; clean = true; historial = false // Ctrl+U: borra también la elección del historial
            case 0x7F, 0x08:
                while let last = buffer.popLast(), last & 0xC0 == 0x80 {}     // (un carácter UTF-8 entero)
            case 0x1B: escape = .started
            case 0x12, 0x10, 0x0E:                               // Ctrl+R, Ctrl+P y Ctrl+N: historial de la shell
                check(io); clean = false; historial = true
            case 0..<0x20: check(io); clean = false               // Tab, Ctrl+R…: lo enviado, en la pantalla
            default: check(io); buffer.append(b)
            }
        }
    }

    private func mask(_ why: String) {
        if !masked { maskedBy = why }
        masked = true
    }

    /// Con la primera tecla que cambia la línea (no con los marcadores del pegado): ¿ha contestado el equipo a la anterior?
    private func check(_ io: TerminalIO) {
        guard !checked else { return }
        checked = true
        if !PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) { mask("sin-prompt") }
        // (lo recolocado caduca: tras «clear⏎» o «tmux attach⏎», la orden de un minuto después sí se mira)
        if let row = lastEnterRow, io.cursorRow == row || (realigned && justEntered) { mask("misma-fila") }
    }

    /// Otro equipo u otro proceso: lo que había a medias en la línea (y el último Intro) era de antes.
    public func resetLine() {
        reset()
        lastEnterRow = nil
        realigned = false
    }

    /// El búfer se ha recolocado (otro tamaño, pantalla alternativa…): si hubo un Intro hace nada (un pegado
    /// troceado), lo siguiente se enmascara: no se sabe si el equipo ha contestado. Pasado un rato (salir de less o
    /// de vi y escribir otra orden), no: se perdería la orden siguiente.
    public func bufferRealigned() {
        if lastEnterRow != nil, justEntered { realigned = true }
    }

    /// Consume las órdenes recogidas sin perder el estado del teclado ni la protección tras Intro.
    public func takeLines() -> [String] {
        defer { lines.removeAll(keepingCapacity: true) }
        return lines
    }

    /// Los pasos grabados: cada línea seguida de «esperar prompt».
    public var steps: [MacroStep] { Macro.recorded(lines) }

    private func finish(_ io: TerminalIO) {
        defer { reset() }
        let typed = !buffer.isEmpty || !clean
        guard typed else { return }
        defer { lastEnterRow = io.cursorRow; lastEnterAt = now(); realigned = false }
        lastDrop = nil
        guard !masked, !SecretPrompt.asks(io.cursorLine), !awaitingAuth(io) else {
            lastDrop = maskedBy ?? (SecretPrompt.asks(io.cursorLine) ? "enmascarada-secreto" : "autenticando")
            skipped += 1
            return
        }
        var line: String?
        if clean {
            line = String(decoding: buffer, as: UTF8.self)
        } else if allowScreenFallback, let s = start, !s.trimmed.isEmpty, io.cursorLine.hasPrefix(s) {
            line = String(io.cursorLine.dropFirst(s.count))
        } else if allowScreenFallback, soloConexiones, historial, let s = start,
                  PromptRule.isPrompt(s, custom: io.promptRule), io.cursorLine.hasPrefix("(reverse-i-search)"),
                  let separator = io.cursorLine.range(of: "': ", options: .backwards) {
            line = String(io.cursorLine[separator.upperBound...])
        }
        if !clean, soloConexiones {
            // (Tab no convierte un «show …» en una conexión; las flechas eligen una orden del historial)
            let typed = String(decoding: buffer, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init)
            let selected = line?.split(whereSeparator: \.isWhitespace).first.map(String.init)
            if line == nil {
                lastDrop = "sin-prefijo"
            } else if (!historial && !["ssh", "telnet"].contains(typed ?? "")) || !["ssh", "telnet"].contains(selected ?? "") {
                line = nil
                lastDrop = "no-conexion"
            }
        }
        guard let l = line?.trimmed, !l.isEmpty, !SessionFile.hasControl(l), l.count <= MacroStep.maxLine else {
            if line == nil { skipped += 1; lastDrop = lastDrop ?? "sin-prefijo" }
            return
        }
        lines.append(l)
    }

    private func reset() {
        buffer = []
        clean = true
        start = nil
        masked = false
        checked = false
        escape = .none
        historial = false
    }
}

// MARK: - reproducir

public struct MacroReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case completed
        case aborted                                       // Esc / Ctrl+C / botón
        case deviceError(step: Int, output: String)        // «% Invalid input…»
        case pager(step: Int)                              // «--More--»
        case timeout(step: Int)
        case dangerousNotConfirmed(step: Int, command: String)
        case secretPrompt(step: Int)                       // piden contraseña/OTP: nada se escribe ahí
        case invalid(String)
    }

    /// Órdenes enviadas.
    public var sent: Int
    public var total: Int
    public var outcome: Outcome
}

/// Reproduce una macro en un terminal con las protecciones del pegado seguro (`SafePaster`, `PasteRules`): antes de
/// cada orden, nada de peligrosas sin confirmar, ni Esc, ni una petición de secreto o un paginador en el cursor; las
/// esperas se paran ante un error del equipo, un paginador o una petición de contraseña, y tienen su timeout.
public struct MacroPlayer: Sendable {
    public var allowDangerous = false
    public var poll: Duration = .milliseconds(100)
    public var quiet: Duration = .milliseconds(500)
    /// Las esperas implícitas entre envíos (y tras el último) también tienen límite.
    public var lineTimeout: Duration = .seconds(20)
    /// El reloj de las esperas (las pruebas ponen uno que no depende de cuándo despierte la tarea).
    public var clock: any PollClock = SystemPollClock()

    public init(allowDangerous: Bool = false) {
        self.allowDangerous = allowDangerous
    }

    @MainActor
    public func run(_ macro: Macro, on io: TerminalIO, abort: AbortSwitch) async -> MacroReport {
        let total = macro.lines.count
        var sent = 0
        func report(_ o: MacroReport.Outcome) -> MacroReport { .init(sent: sent, total: total, outcome: o) }
        if let p = macro.problem { return report(.invalid(p)) }
        let prompt = DevicePrompt(sample: io.cursorLine, custom: io.promptRule)
        var mark = io.cursorRow
        var unchecked = false                                  // (una orden enviada sin llegar a su prompt)
        var lastSendStep = 0
        @MainActor
        func wait(_ timeout: Duration, step: Int, errorStep: Int? = nil) async throws -> MacroReport.Outcome? {
            var p = SafePaster()
            p.lineTimeout = timeout
            p.quiet = quiet
            p.poll = poll
            p.clock = clock
            // (un texto intermedio o el silencio no autorizan a escribir la siguiente orden)
            switch try await p.waitForDevice(io, after: mark, prompt: prompt, abort: abort, allowQuietFallback: false) {
            case .ready: return nil
            case .error(let out): return .deviceError(step: errorStep ?? step, output: out)
            case .pager: return .pager(step: step)
            case .password: return .secretPrompt(step: step)
            case .timeout: return .timeout(step: step)
            }
        }
        do {
            for (i, step) in macro.steps.enumerated() {
                let n = i + 1
                try abort.check()
                switch step.kind {
                case .send:
                    if !allowDangerous, PasteRules.dangerous.matches(step.text) {
                        return report(.dangerousNotConfirmed(step: n, command: step.text))
                    }
                    if unchecked {
                        if let stop = try await wait(lineTimeout, step: n, errorStep: lastSendStep) { return report(stop) }
                        unchecked = false
                    }
                    if SecretPrompt.asks(io.cursorLine) { return report(.secretPrompt(step: n)) }
                    if PasteRules.pager.matches(io.cursorLine) { return report(.pager(step: n)) }
                    if PasteRules.errors.matches(io.cursorLine) || PromptRule.authenticationFailed(io.cursorLine) {
                        return report(.deviceError(step: n, output: io.cursorLine.trimmed))
                    }
                    try abort.check()                          // (justo antes de enviar)
                    mark = io.cursorRow
                    io.sendLine(step.text)
                    sent += 1
                    lastSendStep = n
                    unchecked = true
                case .prompt:
                    let timeout = Duration.milliseconds(Int(step.seconds * 1000))
                    if unchecked {
                        if let stop = try await wait(timeout, step: n) { return report(stop) }
                    } else {
                        // (también sin orden pendiente, los riesgos mandan sobre la coincidencia)
                        let hit: SafePaster.Wait? = try await Poll.until(every: poll, timeout: timeout, abort: abort, clock: clock) {
                            let cur = io.cursorLine
                            if PasteRules.errors.matches(cur) || PromptRule.authenticationFailed(cur) { return .error(cur.trimmed) }
                            if SecretPrompt.asks(cur) { return .password }
                            if PasteRules.pager.matches(cur) { return .pager }
                            return prompt.matches(cur) ? .ready : nil
                        }
                        switch hit {
                        case .ready?: break
                        case .error(let out)?: return report(.deviceError(step: n, output: out))
                        case .password?: return report(.secretPrompt(step: n))
                        case .pager?: return report(.pager(step: n))
                        case .timeout?, nil: return report(.timeout(step: n))
                        }
                    }
                    unchecked = false
                case .text:
                    guard let re = Pattern(compiling: step.text) else { return report(.invalid(step.text)) }
                    enum Hit { case found, error(String), pager, secret }
                    let from = mark + 1
                    let hit: Hit? = try await Poll.until(every: poll, timeout: .milliseconds(Int(step.seconds * 1000)), abort: abort, clock: clock) {
                        let cur = io.cursorLine
                        // (lo salido tras la orden; sin orden, la línea del cursor)
                        let new = io.cursorRow >= from ? io.lines(from: from) : (unchecked ? [] : [cur])
                        let output = unchecked ? io.lines(from: mark) : [cur]
                        if let bad = output.first(where: { PasteRules.errors.matches($0) || PromptRule.authenticationFailed($0) }) {
                            return .error(bad.trimmed)
                        }
                        if output.contains(where: SecretPrompt.asks) { return .secret }
                        if PasteRules.pager.matches(cur) { return .pager }
                        if new.suffix(40).contains(where: { re.matches(String($0.prefix(400))) }) { return .found }
                        return nil
                    }
                    switch hit {
                    case .found?: break                       // (aún falta el prompt antes de volver a enviar)
                    case .error(let out)?: return report(.deviceError(step: n, output: out))
                    case .pager?: return report(.pager(step: n))
                    case .secret?: return report(.secretPrompt(step: n))
                    case nil: return report(.timeout(step: n))
                    }
                case .pause:
                    let _: Bool? = try await Poll.until(every: poll, timeout: .milliseconds(Int(step.seconds * 1000)), abort: abort, clock: clock) { nil }
                }
            }
            if unchecked, let stop = try await wait(lineTimeout, step: macro.steps.count) { return report(stop) }
            return report(.completed)
        } catch {
            return report(.aborted)                            // Esc / Ctrl+C (o la tarea cancelada)
        }
    }
}

public extension MultiExecGroup {
    /// La macro en todos los paneles que aceptan lo repartido (ni los que se autentican ni los pausados), a la vez.
    func run(_ macro: Macro, player: MacroPlayer, abort: AbortSwitch) async -> [MacroReport] {
        let tasks = terminals.filter(accepts).map { io in Task { @MainActor in await player.run(macro, on: io, abort: abort) } }
        var out: [MacroReport] = []
        for t in tasks { out.append(await t.value) }
        return out
    }
}
