import Foundation
import Security

/// Llavero de macOS. Los secretos se leen y guardan con /usr/bin/security, como NetDeck: las contraseñas guardadas así
/// (con «pw» o desde aquí) confían en esa herramienta y NUNCA sale el aviso «… quiere usar la información confidencial»
/// (que con una app sin firmar volvería a salir en cada compilación). Comprobar y listar usan SecItem sin leer el
/// secreto: tampoco piden permiso. Nunca se guarda una contraseña en un archivo.
public struct KeychainStore: CredentialStore {
    public static let tool = "/usr/bin/security"

    typealias Run = @Sendable ([String], String?) throws -> (status: Int32, output: String, error: String)
    /// `security` y la búsqueda con SecItem (las pruebas ponen las suyas: sin tocar tu Llavero).
    private let run: Run
    private let lookup: @Sendable ([String: Any]) -> OSStatus

    public init() {
        run = { try KeychainStore.security($0, input: $1) }
        lookup = { SecItemCopyMatching($0 as CFDictionary, nil) }
    }

    init(run: @escaping Run, lookup: @escaping @Sendable ([String: Any]) -> OSStatus) {
        self.run = run
        self.lookup = lookup
    }

    public func password(for ref: CredentialRef) throws -> String? {
        // «-g» y no «-w»: con «-w» una contraseña con ñ, €, º, \… sale en hexadecimal sin avisar (y se escribía ESO,
        // que no vale: fallo y bloqueo de 15 min de la cuenta AD). «-g» la da entre comillas o como «0x…», sin dudas.
        let r = try run(["find-generic-password", "-s", ref.service.rawValue, "-a", ref.account, "-g"], nil)
        if r.status == 44 { return nil }                          // (errSecItemNotFound)
        guard r.status == 0 else { throw KeychainError(message: r.error) }
        guard let pw = Self.decodePassword(r.error) else { throw KeychainError(message: L("no se entiende la contraseña que devuelve")) }
        return pw
    }

    /// La línea «password: …» de «security find-generic-password -g» (va por stderr): «"texto"» tal cual (dentro
    /// no se escapa nada) o «0x70C3A4…  "p\303\244…"» en hexadecimal (UTF-8). nil si no se entiende.
    static func decodePassword(_ stderr: String) -> String? {
        guard let line = stderr.components(separatedBy: "\n").last(where: { $0.hasPrefix("password:") }) else { return nil }
        let v = line.dropFirst("password:".count).drop { $0 == " " }
        if v.isEmpty { return "" }
        if v.hasPrefix("0x") {
            let hex = Array(v.dropFirst(2).prefix { $0.isHexDigit }.utf8)
            guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
            var bytes: [UInt8] = []
            for i in stride(from: 0, to: hex.count, by: 2) {
                guard let b = UInt8(String(decoding: hex[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
                bytes.append(b)
            }
            return String(bytes: bytes, encoding: .utf8)
        }
        guard v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\"") else { return nil }
        return String(v.dropFirst().dropLast())
    }

    public func contains(_ ref: CredentialRef) -> Bool { (try? exists(ref)) ?? false }

    /// «No está» (errSecItemNotFound) es false; bloqueado, sin permiso para preguntar… es un error.
    public func exists(_ ref: CredentialRef) throws -> Bool {
        var q = query(ref)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let st = lookup(q)
        if st == errSecSuccess { return true }
        if st == errSecItemNotFound { return false }
        throw KeychainError(message: (SecCopyErrorMessageString(st, nil) as String?) ?? "error \(st)")
    }

    public func save(_ password: String, for ref: CredentialRef) throws {
        // Por la entrada estándar («security -i»), no en los argumentos: ahí la vería cualquiera con «ps».
        try add(Self.saveCommand(password, for: ref), ref: ref)
    }

    /// Alta sin sustituir una cuenta que haya aparecido desde que se abrió el formulario.
    public func create(_ password: String, for ref: CredentialRef) throws {
        try add(Self.saveCommand(password, for: ref, replaceExisting: false), ref: ref)
    }

    /// `security -i` sale con 0 aunque la orden falle: se mira lo que dice y, después, que la entrada esté. Su salida
    /// nunca va al mensaje ni a los registros (podría repetir la orden, con la contraseña): un motivo fijo.
    private func add(_ cmd: String, ref: CredentialRef) throws {
        let r = try run(["-i"], cmd + "\n")
        if r.error.localizedCaseInsensitiveContains("already exists") {
            throw KeychainError(message: L("Ya existe una contraseña con ese nombre o cuenta"))
        }
        let saved = r.status == 0 && !r.error.localizedCaseInsensitiveContains("error") && ((try? exists(ref)) ?? false)
        guard saved else {
            ErrorLog.error("llavero", "«\(ref)» no se ha guardado (security -i: código \(r.status), \(r.error.isEmpty ? "sin" : "con") aviso)")
            throw KeychainError(message: L("no se ha podido guardar la contraseña"))
        }
    }

    /// La validación ocurre antes de arrancar `security`; se puede probar sin acceder al Llavero.
    static func saveCommand(_ password: String, for ref: CredentialRef, replaceExisting: Bool = true) throws -> String {
        try CredentialValidation.validate(password, for: ref)
        let label = ref.service == .device ? "NetDeck ssh \(ref.account)" : "NetDeck \(ref.account)"
        var args = ["add-generic-password"]
        if replaceExisting { args.append("-U") }
        args += ["-s", ref.service.rawValue, "-a", ref.account, "-l", label, "-w", password]
        let cmd = args.map(Self.quoted).joined(separator: " ")
        // (security -i lee cada orden con un búfer de 4095 bytes: más larga, se guardaría cortada)
        guard cmd.utf8.count < maxCommand else { throw KeychainError(message: L("el nombre de la cuenta es demasiado largo")) }
        return cmd
    }

    /// Lo más que cabe en una orden de «security -i» (con margen).
    static let maxCommand = 4000

    public func delete(_ ref: CredentialRef) throws {
        let r = try run(["delete-generic-password", "-s", ref.service.rawValue, "-a", ref.account], nil)
        guard r.status == 0 || r.status == 44 else { throw KeychainError(message: r.error) }
    }

    public func accounts(in service: CredentialRef.Service) throws -> [String] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return [] }
        guard st == errSecSuccess, let items = out as? [[String: Any]] else {
            throw KeychainError(message: (SecCopyErrorMessageString(st, nil) as String?) ?? "error \(st)")
        }
        return Set(items.compactMap { $0[kSecAttrAccount as String] as? String }).sorted()
    }

    private func query(_ ref: CredentialRef) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: ref.service.rawValue,
         kSecAttrAccount as String: ref.account]
    }

    /// Entre comillas para «security -i» (dentro, sólo «"» y «\\» se escapan).
    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Lo más que se espera a `security` (si macOS pide la contraseña del Llavero y nadie contesta, se corta).
    static let timeout: TimeInterval = 10

    static func security(_ args: [String], input: String? = nil) throws -> (status: Int32, output: String, error: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let inp = Pipe()
        if input != nil { p.standardInput = inp }
        try p.run()
        // (si no ha terminado en `timeout`, se mata: las tuberías se cierran y todo lo de abajo termina)
        let expired = Once()
        let watchdog = DispatchWorkItem { if p.isRunning, expired.take() { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }
        // (las dos salidas a la vez: si una llena su tubería mientras se lee la otra, se quedaría colgado)
        nonisolated(unsafe) var e = Data()
        let reading = DispatchGroup()
        DispatchQueue.global().async(group: reading) { e = err.fileHandleForReading.readDataToEndOfFile() }
        if let input {
            // (con «throws»: si security se cierra antes, error en vez de una excepción que tumba la app)
            do { try inp.fileHandleForWriting.write(contentsOf: Data(input.utf8)) } catch { DebugLog.log("llavero", "security no ha leído la orden") }
            try? inp.fileHandleForWriting.close()
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        reading.wait()
        p.waitUntilExit()
        if expired.isTaken, p.terminationReason == .uncaughtSignal {
            DebugLog.log("llavero", "security no ha contestado en \(Int(timeout)) s: cortado")
            throw KeychainError(message: L("no contesta en \(Int(timeout)) s (¿está bloqueado?)"))
        }
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self).trimmed)
    }
}

public struct KeychainError: LocalizedError, Equatable {
    public let message: String
    public init(message: String) { self.message = message }

    public var errorDescription: String? { L("Llavero: \(message)") }
}
