import Foundation
import Testing
@testable import NetDeckCore

@Suite struct IdiomaTests {
    static let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func laClaveLlevaUnHuecoPorValor() {
        let n = 3, host = "core-01"
        let t: Texto = "\(n) equipos en «\(host)» al 100%"
        #expect(t.clave == "%@ equipos en «%@» al 100%%")
        #expect(t.valores == ["3", "core-01"])
        #expect(Idioma.traducir(t, a: .es) == "3 equipos en «core-01» al 100%")
    }

    @Test func rellenaPorOrdenYPorPosicion() {
        #expect(Idioma.rellenar("%@ de %@", ["a", "b"]) == "a de b")
        #expect(Idioma.rellenar("%2$@ before %1$@", ["a", "b"]) == "b before a")
        #expect(Idioma.rellenar("100%% · %@", ["x"]) == "100% · x")
        #expect(Idioma.rellenar("falta %@ y %@", ["uno"]) == "falta uno y ")      // nunca se cae
        #expect(Idioma.rellenar("50% suelto", []) == "50% suelto")
    }

    @Test func enInglesYSiFaltaEnCastellano() {
        #expect(Idioma.traducir("Conectar", a: .en) == "Connect")
        #expect(Idioma.traducir("Equipo no válido: «\("x")»", a: .en) == "Invalid device: “x”")
        #expect(Idioma.traducir("texto que no está en el diccionario", a: .en) == "texto que no está en el diccionario")
    }

    @Test func mismosHuecosEnLasDosLenguas() {
        func huecos(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }
        for (es, en) in Ingles.textos {
            #expect(huecos(es) == huecos(en), "«\(es)» → «\(en)»")
        }
    }

    @Test func losNombresConocidosEstanEnIngles() {
        for n in Idioma.nombresConocidos { #expect(Ingles.textos[n] != nil, "falta «\(n)»") }
    }

    /// Toda `L("…")` del código tiene su texto en inglés (se compara en forma de código fuente, escapes incluidos).
    @Test func todoElCodigoEstaTraducido() throws {
        let ingles = try String(contentsOf: Self.raiz.appendingPathComponent("Sources/NetDeckCore/Support/Ingles.swift"),
                                encoding: .utf8)
        var faltan: [String] = []
        var total = 0
        for carpeta in ["Sources/TerminalNetDeck", "Sources/NetDeckCore", "Sources/NetDeckSSH"] {
            let dir = Self.raiz.appendingPathComponent(carpeta)
            let archivos = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Ingles.swift" } ?? []
            for a in archivos {
                for clave in ClavesL.en(try String(contentsOf: a, encoding: .utf8)) {
                    total += 1
                    if !ingles.contains("\"\(clave)\":") { faltan.append("\(a.lastPathComponent): \(clave)") }
                }
            }
        }
        #expect(total > 400)
        #expect(faltan.isEmpty, "Sin inglés:\n\(faltan.joined(separator: "\n"))")
    }
}

/// Las claves de los `L("…")` de un archivo Swift, tal como están escritas (interpolaciones → %@, % → %%).
enum ClavesL {
    static func en(_ fuente: String) -> [String] {
        let c = Array(fuente)
        var out: [String] = []
        var i = 0
        while i < c.count {
            if c[i] == "/", i + 1 < c.count, c[i + 1] == "/" { while i < c.count, c[i] != "\n" { i += 1 }; continue }
            if c[i] == "#", i + 1 < c.count, c[i + 1] == "\"" {                        // #"…"#: sin claves
                i += 2
                while i + 1 < c.count, !(c[i] == "\"" && c[i + 1] == "#") { i += 1 }
                i += 2
                continue
            }
            if c[i] == "\"" {
                if let (fin, _) = literal(c, i, &out) { i = fin } else { i += 1 }
                continue
            }
            i += 1
        }
        return out
    }

    /// Lee el literal que empieza en `c[i]` (comillas), anota su clave si va dentro de `L(` y también las de dentro.
    static func literal(_ c: [Character], _ i: Int, _ out: inout [String]) -> (Int, String)? {
        if i + 2 < c.count, c[i + 1] == "\"", c[i + 2] == "\"" { return nil }
        var clave = ""
        var j = i + 1
        while j < c.count {
            switch c[j] {
            case "\\" where j + 1 < c.count && c[j + 1] == "(":
                j = interpolacion(c, j + 2, &out)
                clave += "%@"
            case "\\":
                clave.append(c[j])
                if j + 1 < c.count { clave.append(c[j + 1]) }
                j += 2
            case "%":
                clave += "%%"
                j += 1
            case "\"":
                if i >= 2, c[i - 2] == "L", c[i - 1] == "(" { out.append(clave) }
                return (j + 1, clave)
            case "\n":
                return nil
            default:
                clave.append(c[j])
                j += 1
            }
        }
        return nil
    }

    static func interpolacion(_ c: [Character], _ inicio: Int, _ out: inout [String]) -> Int {
        var j = inicio, nivel = 1
        while j < c.count, nivel > 0 {
            if c[j] == "\"", let (fin, _) = literal(c, j, &out) { j = fin; continue }
            if c[j] == "(" { nivel += 1 } else if c[j] == ")" { nivel -= 1 }
            j += 1
        }
        return j
    }
}
