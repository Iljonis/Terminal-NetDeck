import Foundation

/// El nombre que le pones a una pestaña («Renombrar la pestaña…»): se queda mientras sigas en el mismo equipo (también
/// al reconectar o en el modo configuración) y se quita solo cuando sale el prompt de otro equipo.
public struct TabRename: Hashable, Sendable {
    public private(set) var name: String?
    /// El equipo en el que se puso (nil: aún no había prompt; entonces es el primero que salga).
    public private(set) var device: String?

    public init() {}

    /// Ponerlo (vacío o nil: quitarlo) estando en `device`.
    public mutating func set(_ name: String?, on device: String?) {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = n.isEmpty ? nil : n
        self.device = self.name == nil ? nil : device
    }

    /// Ha salido el prompt de `d`. true si el nombre se ha quitado (es otro equipo).
    @discardableResult
    public mutating func deviceChanged(to d: String) -> Bool {
        guard name != nil else { return false }
        guard let mine = device else { device = d; return false }
        guard mine != d else { return false }
        name = nil
        device = nil
        return true
    }
}
