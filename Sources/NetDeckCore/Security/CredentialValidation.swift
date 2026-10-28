import Foundation

/// Altas y cambios del Llavero: valida los metadatos sin modificar la cuenta ni el secreto.
public enum CredentialValidation {
    /// Lo más largo que se guarda, ya escapada (bytes UTF-8).
    public static let maxPassword = 1024

    public static func validateReference(_ ref: CredentialRef) throws {
        let account = ref.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { throw KeychainError(message: L("falta el nombre o la cuenta de la contraseña")) }
        let controls = CharacterSet.controlCharacters.union(.newlines)
        guard ref.account.unicodeScalars.allSatisfy({ !controls.contains($0) }) else {
            throw KeychainError(message: L("el nombre o la cuenta lleva caracteres de control"))
        }
        switch ref.service {
        case .named:
            guard account != "-" else { throw KeychainError(message: L("«-» está reservado para la contraseña propia del equipo")) }
        case .device:
            // (la última @ separa el equipo: el usuario puede ser un UPN, como usuario@dominio.example)
            guard let at = ref.account.lastIndex(of: "@"), at != ref.account.startIndex,
                  ref.account.index(after: at) != ref.account.endIndex,
                  !ref.account.contains(where: \.isWhitespace) else {
                throw KeychainError(message: L("la cuenta debe tener el formato usuario@equipo, sin espacios"))
            }
        }
    }

    public static func validate(_ password: String, for ref: CredentialRef) throws {
        try validateReference(ref)
        // (sin trim: los espacios, símbolos y Unicode de una contraseña forman parte de ella)
        guard !password.isEmpty else { throw KeychainError(message: L("la contraseña está vacía")) }
        // (escapada para «security -i» tiene que caber en su orden: más larga, se guardaría cortada)
        guard KeychainStore.quoted(password).utf8.count <= maxPassword else {
            throw KeychainError(message: L("la contraseña es demasiado larga (más de \(String(maxPassword)) bytes)"))
        }
        guard !password.contains(where: \.isNewline) else { throw KeychainError(message: L("la contraseña lleva un salto de línea")) }
        guard !password.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw KeychainError(message: L("la contraseña lleva un carácter nulo"))
        }
    }
}
