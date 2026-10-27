import Foundation

/// Renombra una entrada y sólo sus referencias estructuradas. Se ejecuta fuera del hilo principal; no toca órdenes,
/// macros, configuraciones ajenas ni UserDefaults. La entrada anterior se conserva: el llamador actualiza la
/// predeterminada y comprueba las referencias externas antes de decidir si puede borrarla.
public enum CredentialRenamer {
    public struct Paths: Sendable {
        public var sessions: URL
        public var buttons: URL
        public var lists: URL
        public init(sessions: URL, buttons: URL, lists: URL) {
            self.sessions = sessions; self.buttons = buttons; self.lists = lists
        }
        public static var standard: Paths {
            Paths(sessions: SessionFile.defaultURL, buttons: ButtonFile.defaultURL, lists: ListLibrary.defaultURL)
        }
    }

    public enum Failure: LocalizedError {
        case invalidReference, differentService, missingSource, destinationExists, ambiguousList
        case changedFile(String)
        case updateFailed(String, [String])
        public var errorDescription: String? {
            switch self {
            case .invalidReference: L("El nombre o la cuenta de la credencial no es válido")
            case .differentService: L("No se puede cambiar el tipo de una credencial al renombrarla")
            case .missingSource: L("La credencial que quieres renombrar ya no está en el Llavero")
            case .destinationExists: L("Ya existe una credencial con ese nombre o cuenta")
            case .ambiguousList: L("Una lista usa una cuenta compartida por dos tipos de credencial: revísala antes de renombrar")
            case .changedFile(let path): L("El archivo \(path) ha cambiado mientras se renombraba: no se sobrescribe")
            case .updateFailed(let detail, let pending):
                L("No se ha completado el renombrado: \(detail). Se conservan las dos entradas del Llavero")
                    + (pending.isEmpty ? L("; se han restaurado los archivos modificados")
                       : L("; revisa estos archivos antes de borrar ninguna: \(pending.joined(separator: ", "))"))
            }
        }
    }

    /// `password == nil` conserva el secreto anterior; el nuevo se crea sin sustituir ninguna entrada existente.
    /// El callback permite trasladar el bloqueo antes de publicar la primera referencia al nombre nuevo.
    @discardableResult
    public static func rename(from source: CredentialRef, to destination: CredentialRef, password: String? = nil,
                              store: CredentialStore, paths: Paths = .standard,
                              beforeUpdatingReferences: @Sendable () throws -> Void = {}) throws -> Int {
        try rename(from: source, to: destination, password: password, store: store, paths: paths,
                   beforeUpdatingReferences: beforeUpdatingReferences, write: { try SafeFile.write($0, to: $1) })
    }

    public static func renameInBackground(from source: CredentialRef, to destination: CredentialRef, password: String? = nil,
                                          store: CredentialStore, paths: Paths = .standard,
                                          beforeUpdatingReferences: @escaping @Sendable () throws -> Void = {}) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try rename(from: source, to: destination, password: password,
                                                               store: store, paths: paths,
                                                               beforeUpdatingReferences: beforeUpdatingReferences))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private struct Change {
        let url: URL
        let original: String
        let updated: String
        let count: Int
    }

    /// La escritura se inyecta sólo en los tests, para comprobar fallos y conflictos sin tocar el Llavero real.
    static func rename(from source: CredentialRef, to destination: CredentialRef, password: String? = nil,
                       store: CredentialStore, paths: Paths,
                       beforeUpdatingReferences: @Sendable () throws -> Void = {},
                       write: (String, URL) throws -> Void) throws -> Int {
        guard source.service == destination.service else { throw Failure.differentService }
        try CredentialValidation.validateReference(destination)
        guard source != destination, [source.account, destination.account].allSatisfy({
            !$0.trimmed.isEmpty && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }), destination.account == destination.account.trimmed,
              destination.service != .named || destination.account != "-" else { throw Failure.invalidReference }
        if let password, password.isEmpty || password.contains(where: \.isNewline) || password.contains("\0") {
            throw Failure.invalidReference
        }
        guard !store.contains(destination) else { throw Failure.destinationExists }
        guard let previous = try store.password(for: source) else { throw Failure.missingSource }
        var changes: [Change] = []
        for (url, kind) in [(paths.sessions, 0), (paths.buttons, 1), (paths.lists, 2)] {
            guard let text = try SafeFile.read(url) else { continue }
            let result: (String, Int)
            switch kind {
            case 0: result = source.service == .named && source.account != "-"
                    ? replaceLines(text) { session($0, from: source.account, to: destination.account) } : (text, 0)
            case 1:
                result = source.service == .named
                    ? replaceLines(text) { button($0, from: source.account, to: destination.account) } : (text, 0)
            default:
                result = try lists(text, from: source.account, to: destination.account)
                if result.1 > 0 {
                    let other: CredentialRef.Service = source.service == .named ? .device : .named
                    if store.contains(.init(service: other, account: source.account))
                        || store.contains(.init(service: other, account: destination.account)) { throw Failure.ambiguousList }
                }
            }
            if result.1 > 0 { changes.append(Change(url: url, original: text, updated: result.0, count: result.1)) }
        }
        // (todos los archivos existentes se han podido leer y las listas se han validado antes de crear nada)
        try CredentialValidation.validate(password ?? previous, for: destination)
        try store.create(password ?? previous, for: destination)
        var touched: [Change] = []
        do {
            try beforeUpdatingReferences()
            for change in changes {
                guard try matches(change.original, at: change.url) else { throw Failure.changedFile(AppPaths.tilde(change.url.path)) }
                try SafeFile.backup(change.url)
                guard try matches(change.original, at: change.url) else { throw Failure.changedFile(AppPaths.tilde(change.url.path)) }
                touched.append(change)                  // (también si write cambia el archivo y luego falla al poner 0600)
                try write(change.updated, change.url)
            }
            for change in changes {
                guard try matches(change.updated, at: change.url) else { throw Failure.changedFile(AppPaths.tilde(change.url.path)) }
            }
            return changes.reduce(0) { $0 + $1.count }
        } catch {
            var pending: [String] = []
            for change in touched.reversed() {
                do {
                    if try matches(change.updated, at: change.url) { try write(change.original, change.url) }
                    guard try matches(change.original, at: change.url) else { pending.append(AppPaths.tilde(change.url.path)); continue }
                } catch { pending.append(AppPaths.tilde(change.url.path)) }
            }
            // (ni una edición externa se pisa al deshacer; ambas entradas se conservan incluso si el rollback fue bien)
            throw Failure.updateFailed(error.localizedDescription, pending)
        }
    }

    private static func matches(_ original: String, at url: URL) throws -> Bool {
        guard let current = try SafeFile.read(url) else { return false }
        return current.utf8.elementsEqual(original.utf8)
    }

    private static func replaceLines(_ text: String, transform: (String) -> String?) -> (String, Int) {
        var count = 0
        let lines = text.components(separatedBy: "\n").map { line in
            guard let replacement = transform(line) else { return line }
            count += 1
            return replacement
        }
        return (lines.joined(separator: "\n"), count)
    }

    private static func replacingValue(_ value: String, from source: String, to destination: String) -> String? {
        guard value.trimmed == source, let range = value.range(of: source) else { return nil }
        var result = value
        result.replaceSubrange(range, with: destination)
        return result
    }

    private static func session(_ line: String, from source: String, to destination: String) -> String? {
        let trimmed = String(line.drop { $0.isWhitespace && !$0.isNewline })
        for marker in ["# @clave ", "# @clave-grupo "] where trimmed.utf8.starts(with: marker.utf8) {
            let prefix = line.prefix(line.count - trimmed.count) + marker
            guard let value = replacingValue(String(decoding: trimmed.utf8.dropFirst(marker.utf8.count), as: UTF8.self), from: source, to: destination) else { return nil }
            return prefix + value
        }
        return nil
    }

    private static func button(_ line: String, from source: String, to destination: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { return nil }
        let parts = line.components(separatedBy: " :: ")
        guard parts.count >= 4 else { return nil }
        let command = parts[3...].joined(separator: " :: ")
        let replacement: String?
        switch parts[1].trimmed {
        case "pass": replacement = replacingValue(command, from: source, to: destination)
        case "login":
            guard let separator = command.firstIndex(of: "/") else { return nil }
            let user = String(command[..<separator]), credential = String(command[command.index(after: separator)...])
            guard !user.trimmed.isEmpty,
                  let name = replacingValue(credential, from: source, to: destination) else { return nil }
            replacement = user + "/" + name
        default: return nil
        }
        return replacement.map { parts.prefix(3).joined(separator: " :: ") + " :: " + $0 }
    }

    /// Sólo los valores `lists[].credential`: conserva espacios, claves desconocidas y cualquier otro texto JSON.
    private static func lists(_ text: String, from source: String, to destination: String) throws -> (String, Int) {
        _ = try JSONDecoder().decode(ListLibrary.self, from: Data(text.utf8))
        let replacement = Array(try JSONEncoder().encode(destination)), bytes = Array(text.utf8)
        var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0, ranges: [Range<Int>] = []
        func skipSpaces() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        func string() throws -> (String, Range<Int>) {
            let start = index
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 92 { index += 1 }              // (escape JSON: nunca se interpreta como cierre)
                else if byte == 34 { break }
            }
            let range = start..<index
            return (try JSONDecoder().decode(String.self, from: Data(bytes[range])), range)
        }
        func value(_ path: [String]) throws {
            skipSpaces()
            switch bytes[index] {
            case 123:                                    // {
                index += 1; skipSpaces()
                while bytes[index] != 125 {
                    let (key, _) = try string()
                    skipSpaces(); index += 1
                    try value(path + [key]); skipSpaces()
                    if bytes[index] != 44 { break }
                    index += 1; skipSpaces()
                }
                index += 1
            case 91:                                     // [
                index += 1; skipSpaces()
                while bytes[index] != 93 {
                    try value(path + ["[]"]); skipSpaces()
                    if bytes[index] != 44 { break }
                    index += 1; skipSpaces()
                }
                index += 1
            case 34:
                let (name, range) = try string()
                if path == ["lists", "[]", "credential"], name == source { ranges.append(range) }
            default:
                while index < bytes.count, ![44, 93, 125, 9, 10, 13, 32].contains(bytes[index]) { index += 1 }
            }
        }
        try value([])
        var result = bytes
        for range in ranges.reversed() { result.replaceSubrange(range, with: replacement) }
        return (String(decoding: result, as: UTF8.self), ranges.count)
    }
}
