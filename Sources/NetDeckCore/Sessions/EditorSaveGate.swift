import Foundation
import Observation

/// El editor de sesiones mientras se guardan: nada que lo cierre, abra pestañas o vuelva a guardar hasta que acabe (lo
/// que se cambie mientras tanto, y el aviso de si ha ido bien, siguen en la hoja). Lo usan los botones (desactivados) y
/// cada acción por dentro (por si llega por otro camino: atajo, menú, una tarea que termina).
@MainActor @Observable
public final class EditorSaveGate {
    public enum Action: Sendable { case save, connect, close, finish }

    public private(set) var saving = false

    public init() {}

    /// Empieza a guardar; false si ya se estaba guardando.
    public func begin() -> Bool {
        guard !saving else { return false }
        saving = true
        return true
    }

    public func end() { saving = false }

    /// nil = se puede; si no, el aviso para el usuario.
    public func blocks(_ action: Action) -> String? {
        saving ? L("Espera a que terminen de guardarse") : nil
    }
}
