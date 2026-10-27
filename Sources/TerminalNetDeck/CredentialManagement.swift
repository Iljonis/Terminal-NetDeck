import Foundation
import NetDeckCore

extension AppModel {
    /// Un cambio cada vez entre todas las ventanas; renombrar nunca pisa otro secreto ni un borrador de sesiones.
    func guardarCredencial(from source: CredentialRef?, to target: CredentialRef, password: String?) async throws -> String {
        guard !core.editingCredential else { throw KeychainError(message: L("Ya se está modificando una credencial")) }
        try CredentialValidation.validateReference(target)
        if let password { try CredentialValidation.validate(password, for: target) }
        core.editingCredential = true
        defer { core.editingCredential = false; keychainRevision += 1 }
        guard let source else {
            guard let password else { throw KeychainError(message: L("la contraseña está vacía")) }
            try await store.createInBackground(password, for: target)
            ledger.reset(target)
            return L("Guardada ✓ (\(target.account))")
        }
        if source == target {
            if let password {
                try await store.saveInBackground(password, for: target)
                ledger.reset(target)
            }
            return L("Guardada ✓ (\(target.account))")
        }
        guard sharedEditorElsewhere == nil, sheet == nil, settingsLeave == nil else {
            throw KeychainError(message: L("Guarda y cierra los otros editores antes de renombrar una credencial"))
        }
        if transfers.active > 0 || core.allBrowsers.contains(where: { $0.1.isFTP && $0.1.state == .connected }) {
            throw KeychainError(message: L("Desconecta FTP y espera a que terminen las transferencias antes de renombrar"))
        }
        if core.allBrowsers.contains(where: { $0.1.state == .connecting }) || tunnelRunner.states.values.contains(.starting)
            || core.allTabs.contains(where: {
            if let browser = $0.browser { return browser.state == .connecting }
            return $0.route.usesPasswords && !$0.loggedIn && !$0.exited
        }) {
            throw KeychainError(message: L("Espera a que termine la autenticación pendiente antes de renombrar"))
        }
        if case .probing = ledger.state(of: source) {
            throw KeychainError(message: L("Espera a que termine la autenticación pendiente antes de renombrar"))
        }
        core.renamingCredential = true
        defer { core.renamingCredential = false }
        core.allTabs.forEach { $0.cancelPasswordContext() }
        let ledger = ledger
        do {
            _ = try await CredentialRenamer.renameInBackground(from: source, to: target, password: password, store: store) {
                guard ledger.copyFailure(from: source, to: target) else {
                    throw KeychainError(message: L("Espera a que termine la autenticación pendiente antes de renombrar"))
                }
            }
        } catch {
            // (un error parcial conserva las dos entradas; recargar también refleja cualquier referencia conservada)
            reloadSessions(); reloadButtons()
            throw error
        }
        if source.service == .named, settings.defaultCredentialName == source.account {
            settings.defaultCredentialName = target.account
        }
        if password != nil { ledger.reset(target) }
        reloadSessions(); reloadButtons()
        // (un ssh_config externo o una sesión que sigue apuntando al usuario/equipo antiguo necesita su entrada)
        let stillUsed = sessions.loadError != nil || sessions.profiles.contains { profile in
            if source.service == .named { return profile.namedCredential == source.account }
            return CredentialRef.device(profile.effectiveUser, profile.endpoint.host) == source
        }
        if stillUsed {
            return L("Guardada como «\(target.account)». Se conserva «\(source.account)» porque todavía la usa una sesión o configuración externa.")
        }
        do { try await store.deleteInBackground(source) }
        catch {
            return L("Guardada como «\(target.account)»; no se pudo borrar la entrada anterior: \(error.localizedDescription)")
        }
        return L("Credencial renombrada: \(target.account)")
    }
}
