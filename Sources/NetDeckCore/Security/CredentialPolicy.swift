import Foundation

/// Una contraseña candidata y a qué usuario(s) pertenece.
public struct CredentialCandidate: Hashable, Sendable {
    public enum Origin: String, Sendable { case sessionNamed, device, jumpSession, defaultCredential }

    public var ref: CredentialRef
    /// Dueños: el de «usuario@equipo», los de las sesiones que usan esa con nombre, el de la por defecto.
    /// Vacío = no se sabe de quién es (sólo vale si tampoco se sabe qué usuario pide).
    public var owners: Set<String>
    public var origin: Origin

    public init(ref: CredentialRef, owners: Set<String>, origin: Origin) {
        self.ref = ref
        self.owners = owners
        self.origin = origin
    }
}

public enum ManualReason: Equatable, Sendable {
    /// Nueva / repetir / actual: la escribes tú.
    case changeOrConfirm
    /// El usuario pedido no es el de ninguna guardada (p. ej. «ssh root@…» con la por defecto de otro usuario).
    case userMismatch(requested: String)
    /// La orden dice un usuario y el prompt otro: no se arriesga.
    case conflictingUsers(command: String, prompt: String)
    /// Falló hace poco en otra pestaña: otra vez bloquearía la cuenta AD.
    case recentlyFailed(CredentialRef)
    /// No hay ninguna guardada que valga.
    case noCredential
}

public enum InjectionDecision: Equatable, Sendable {
    case inject(CredentialRef)
    case manual(ManualReason)
}

/// REGLA DE USUARIO: una contraseña sólo se escribe sola si es exactamente del usuario que la pide — el de la orden
/// ssh/telnet (`ssh root@…`, `-l pepe`) o el del prompt («Username: pepe», «(admin@equipo) Enter password:»). Si no
/// coincide, si se contradicen o si falló hace poco, nada se escribe: eliges tú a mano.
public struct CredentialPolicy: Sendable {
    /// «Password:» a secas y sin usuario en la orden: ¿vale la primera candidata? (NetDeck: sí)
    public var allowWhenUserUnknown: Bool

    public init(allowWhenUserUnknown: Bool = true) {
        self.allowWhenUserUnknown = allowWhenUserUnknown
    }

    public func decide(_ request: PasswordRequest, commandUser: String?, candidates: [CredentialCandidate],
                       isBlocked: (CredentialRef) -> Bool) -> InjectionDecision {
        if request.isChangeOrConfirm { return .manual(.changeOrConfirm) }
        // «usuario@equipo» en la petición manda (con «ssh -J» primero piden la del salto, de otro usuario);
        // si sólo hay el tecleado en «Username:» y la orden decía otro, no se arriesga.
        if request.account == nil, let c = commandUser, let t = request.typedUser, c != t {
            return .manual(.conflictingUsers(command: c, prompt: t))
        }
        let wanted = request.account != nil ? request.user : (request.typedUser ?? commandUser)
        if wanted == nil, !allowWhenUserUnknown { return .manual(.noCredential) }
        var mismatch = false
        for c in candidates {
            if let w = wanted, !c.owners.contains(w) {          // exacto: «Admin» no es «admin»
                mismatch = true
                continue
            }
            if isBlocked(c.ref) { return .manual(.recentlyFailed(c.ref)) }
            return .inject(c.ref)
        }
        if mismatch, let w = wanted { return .manual(.userMismatch(requested: w)) }
        return .manual(.noCredential)
    }
}
