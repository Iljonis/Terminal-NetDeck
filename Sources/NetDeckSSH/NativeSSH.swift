import Foundation
import NIOCore
import NIOSSH
import NetDeckCore

/// Fase 2: SSH nativo con SwiftNIO SSH (sin /usr/bin/ssh). De momento, la autenticación: contraseña del Llavero con
/// la misma regla de usuario, y UN solo intento por conexión (una rechazada no se repite: cuentas AD).
public final class KeychainPasswordAuthenticator: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let target: Endpoint
    private let candidates: [CredentialCandidate]
    private let blocked: Set<CredentialRef>
    private let store: CredentialStore
    private let policy: CredentialPolicy
    private let lock = NSLock()
    private var offered = false

    /// `blocked`: las que `CredentialLedger` tiene bloqueadas al abrir la conexión.
    public init(target: Endpoint, candidates: [CredentialCandidate], blocked: Set<CredentialRef>,
                store: CredentialStore, policy: CredentialPolicy = .init()) {
        self.target = target
        self.candidates = candidates
        self.blocked = blocked
        self.store = store
        self.policy = policy
    }

    public func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                       nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        let first = lock.withLock { () -> Bool in
            defer { offered = true }
            return !offered
        }
        guard first, availableMethods.contains(.password), let user = target.user else {
            return nextChallengePromise.succeed(nil)              // nada más que ofrecer: se elige a mano
        }
        let request = PasswordRequest(line: "", account: "\(user)@\(target.host)", typedUser: nil, isChangeOrConfirm: false)
        guard case .inject(let ref) = policy.decide(request, commandUser: user, candidates: candidates,
                                                     isBlocked: blocked.contains),
              let pw = try? store.password(for: ref) else {
            return nextChallengePromise.succeed(nil)
        }
        nextChallengePromise.succeed(.init(username: user, serviceName: "", offer: .password(.init(password: pw))))
    }
}

public enum NativeSSHError: LocalizedError {
    case notImplemented

    public var errorDescription: String? { L("SSH nativo: pendiente (fase 2); se usa /usr/bin/ssh") }
}

/// Pendiente: ClientBootstrap + NIOSSHHandler(role: .client(…)) + canal «session» con pty, unido a `TerminalIO`;
/// los saltos como canales «direct-tcpip» encadenados.
public struct NativeSSHTransport: Sendable {
    public var route: ConnectionRoute

    public init(route: ConnectionRoute) {
        self.route = route
    }

    public func connect() async throws {
        throw NativeSSHError.notImplemented
    }
}
