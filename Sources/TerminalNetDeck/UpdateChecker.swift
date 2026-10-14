import Foundation
import NetDeckCore

/// Actualizaciones en segundo plano: al arrancar (si han pasado más de 24 h desde la última consulta) y luego una vez
/// al día mientras la app sigue abierta. En silencio: sin red, sin releases o con error no se dice nada; si hay una
/// versión nueva sólo aparece un aviso discreto en la barra de estado (`AppModel.availableUpdate`). Nunca descarga ni
/// instala nada sin que lo pidas.
@MainActor
final class UpdateChecker {
    static let lastCheckKey = "ultimaComprobacionActualizaciones"
    static let interval: TimeInterval = 24 * 60 * 60

    private weak var model: AppModel?
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private var checking = false

    init(model: AppModel) {
        self.model = model
    }

    /// Empieza: consulta ya si toca y vuelve a mirar cada hora si ha pasado el día.
    func start() {
        checkIfDue()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    /// ¿Ha pasado el día desde la última consulta?
    static func isDue(last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || last > now        // (reloj cambiado hacia atrás)
    }

    private func checkIfDue() {
        guard let model, model.settings.autoUpdateCheck, let repo = UpdateCheck.repo,
              Self.isDue(last: defaults.object(forKey: Self.lastCheckKey) as? Date) else { return }
        guard !checking else { return }
        checking = true
        Task { [weak self] in
            defer { self?.checking = false }
            do {
                let release = try await UpdateCheck.check(repo: repo)
                // (sólo si ha contestado: sin red o con error se reintenta en la próxima vuelta del temporizador)
                self?.defaults.set(Date(), forKey: Self.lastCheckKey)
                self?.model?.availableUpdate = release
                DebugLog.log("actualizaciones", release.map { "hay una nueva: \($0.version)" } ?? "al día")
            } catch {
                ErrorLog.warning("actualizaciones", "sin respuesta: \(error.localizedDescription)")
            }
        }
    }
}
