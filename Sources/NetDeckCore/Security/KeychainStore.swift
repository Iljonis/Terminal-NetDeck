import Foundation
import Security

/// Llavero de macOS. Los secretos se leen y guardan con /usr/bin/security, como NetDeck: las contraseñas guardadas así
/// (con «pw» o desde aquí) confían en esa herramienta y NUNCA sale el aviso «… quiere usar la información confidencial»
/// (que con una app sin firmar volvería a salir en cada compilación). Comprobar y listar usan SecItem sin leer el
/// secreto: tampoco piden permiso. Nunca se guarda una contraseña en un archivo.
public struct KeychainStore: CredentialStore {
    public static let tool = "/usr/bin/security"

    public init() {}

    public func password(for ref: CredentialRef) throws -> String? {
        let r = try Self.security(["find-generic-password", "-s", ref.service.rawValue, "-a", ref.account, "-w"])
        if r.status == 44 { return nil }                          // (errSecItemNotFound)
        guard r.status == 0 else { throw KeychainError(message: r.error) }
        return r.output.hasSuffix("\n") ? String(r.output.dropLast()) : r.output
    }

    public func contains(_ ref: CredentialRef) -> Bool {
        var q = query(ref)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    public func save(_ password: String, for ref: CredentialRef) throws {
        let label = ref.service == .device ? "NetDeck ssh \(ref.account)" : "NetDeck \(ref.account)"
        guard !password.contains(where: \.isNewline) else { throw KeychainError(message: L("la contraseña lleva un salto de línea")) }
        // Por la entrada estándar («security -i»), no en los argumentos: ahí la vería cualquiera con «ps».
        let cmd = ["add-generic-password", "-U", "-s", ref.service.rawValue, "-a", ref.account, "-l", label, "-w", password]
            .map(Self.quoted).joined(separator: " ")
        let r = try Self.security(["-i"], input: cmd + "\n")
        guard r.status == 0, !r.error.contains("error") else { throw KeychainError(message: r.error) }
    }

    public func delete(_ ref: CredentialRef) throws {
        let r = try Self.security(["delete-generic-password", "-s", ref.service.rawValue, "-a", ref.account])
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
        if let input {
            inp.fileHandleForWriting.write(Data(input.utf8))
            try? inp.fileHandleForWriting.close()
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self).trimmed)
    }
}

public struct KeychainError: LocalizedError, Equatable {
    public let message: String

    public var errorDescription: String? { L("Llavero: \(message)") }
}
