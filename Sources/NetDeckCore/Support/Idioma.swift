import Foundation
import Synchronization

/// Idioma de la interfaz: castellano de España (el del código) o inglés. Los textos se escriben en castellano con
/// `L("…")`; en inglés se buscan en `Ingles.textos`, cuya clave es el texto con «%@» en lugar de cada valor
/// interpolado (`L("\(n) equipos")` → «%@ equipos»). Lo que falte en inglés sale en castellano.
public enum Idioma: String, CaseIterable, Identifiable, Sendable {
    case es, en

    public var id: String { rawValue }
    /// Su nombre en su propio idioma (en el selector no se traduce).
    public var nombre: String { self == .es ? "Español (España)" : "English" }

    /// Clave en UserDefaults (la app y su askpass, que es el mismo ejecutable, leen la misma).
    public static let clave = "idioma"

    private static let guardado = Mutex<Idioma>(UserDefaults.standard.string(forKey: clave).flatMap(Idioma.init) ?? .sistema)

    public static var actual: Idioma {
        get { guardado.withLock { $0 } }
        set { guardado.withLock { $0 = newValue } }
    }

    /// El del sistema: castellano si el primer idioma preferido lo es; si no, inglés.
    public static var sistema: Idioma {
        (Locale.preferredLanguages.first ?? "es").hasPrefix("es") ? .es : .en
    }

    /// El texto en ese idioma (por defecto, el actual).
    public static func traducir(_ t: Texto, a idioma: Idioma = actual) -> String {
        let plantilla = idioma == .en ? (Ingles.textos[t.clave] ?? t.clave) : t.clave
        return rellenar(plantilla, t.valores)
    }

    /// «%@» por orden, «%2$@» por posición, «%%» → «%».
    static func rellenar(_ plantilla: String, _ valores: [String]) -> String {
        guard plantilla.contains("%") else { return plantilla }
        let c = Array(plantilla)
        var out = ""
        var siguiente = 0
        var i = 0
        while i < c.count {
            guard c[i] == "%", i + 1 < c.count else { out.append(c[i]); i += 1; continue }
            if c[i + 1] == "%" { out.append("%"); i += 2; continue }
            if c[i + 1] == "@" {
                out += siguiente < valores.count ? valores[siguiente] : ""
                siguiente += 1
                i += 2
                continue
            }
            var k = i + 1, n = 0                                    // «%N$@»
            while k < c.count, let d = c[k].wholeNumberValue { n = n * 10 + d; k += 1 }
            if n > 0, k + 1 < c.count, c[k] == "$", c[k + 1] == "@" {
                out += n <= valores.count ? valores[n - 1] : ""
                i = k + 2
                continue
            }
            out.append(c[i])
            i += 1
        }
        return out
    }
}

/// Un texto de la interfaz con sus valores: la clave lleva «%@» en su lugar (y «%%» por cada «%» literal).
public struct Texto: ExpressibleByStringInterpolation, Sendable, Equatable {
    public var clave: String
    public var valores: [String]

    public init(stringLiteral value: String) {
        clave = value.replacingOccurrences(of: "%", with: "%%")
        valores = []
    }

    public init(stringInterpolation: Interpolacion) {
        clave = stringInterpolation.clave
        valores = stringInterpolation.valores
    }

    public struct Interpolacion: StringInterpolationProtocol {
        var clave = ""
        var valores: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            clave += literal.replacingOccurrences(of: "%", with: "%%")
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            clave += "%@"
            valores.append(String(describing: value))
        }
    }
}

/// El texto en el idioma de la interfaz.
public func L(_ t: Texto) -> String { Idioma.traducir(t) }

/// Un nombre que viene de datos (grupo de temas o de sesiones): se traduce si es uno de los conocidos
/// (`Idioma.nombresConocidos`); los que pone el usuario quedan tal cual.
public func L(nombre: String) -> String { Idioma.traducir(Texto(stringLiteral: nombre)) }

extension Idioma {
    /// Los nombres de datos que se traducen con `L(nombre:)` (IdiomaTests comprueba que estén en inglés).
    public static let nombresConocidos = Theme.groups + ["Sin grupo", "General", "Importadas"]
}
