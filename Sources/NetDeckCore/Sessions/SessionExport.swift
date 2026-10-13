import Foundation

/// Exportar sesiones (todas o de unos grupos) para llevarlas a otro Mac o compartirlas: JSON con todos los campos o CSV
/// con las columnas que entiende el importador. Nunca lleva contraseñas (en el gestor no las hay: están en el Llavero).
/// El JSON se vuelve a importar con `SessionImporter` (que quita las opciones de ssh peligrosas y las repetidas).
public enum SessionExport {
    public static let format = "netdeck-sesiones"

    struct Entry: Codable {
        var grupo: String
        var nombre: String
        var tipo: String
        var descripcion: String?
        var equipo: String?
        var usuario: String?
        var puerto: String?
        var salto: String?
        /// Nombre de la contraseña con nombre del Llavero (nunca la contraseña). Al importar no se aplica: se elige.
        var clave: String?
        var claveFile: String?
        var antiguo: Bool?
        var serie: String?
        var notas: [String]?
        var opciones: [String]?
    }

    struct Document: Codable {
        var formato: String
        var version: Int
        var sesiones: [Entry]
    }

    /// Las sesiones de esos grupos (y de sus subcarpetas); nil = todas.
    public static func select(_ sessions: [EditableSession], groups: Set<String>?) -> [EditableSession] {
        guard let groups else { return sessions }
        return sessions.filter { s in groups.contains { $0 == s.group || GroupTree.contains($0, s.group) } }
    }

    public static func json(_ sessions: [EditableSession]) -> Data {
        func opt(_ s: String) -> String? { s.isEmpty ? nil : s }
        let doc = Document(formato: format, version: 1, sesiones: sessions.map { s in
            Entry(grupo: s.group, nombre: s.name, tipo: s.kind.annotation, descripcion: opt(s.summary), equipo: opt(s.host),
                  usuario: opt(s.user), puerto: opt(s.port), salto: opt(s.jump), clave: opt(s.credential),
                  claveFile: opt(s.keyFile), antiguo: s.legacy ? true : nil,
                  serie: s.kind == .serial ? s.serial.annotation : nil,
                  notas: s.notes.isEmpty ? nil : s.notes, opciones: s.extra.isEmpty ? nil : s.extra)
        })
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(doc)) ?? Data()
    }

    /// CSV con «;» (Excel en castellano) y cabecera: grupo;nombre;host;usuario;puerto;salto;descripcion;tipo.
    public static func csv(_ sessions: [EditableSession]) -> String {
        func cell(_ v: String) -> String {
            let v = v.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
            return v.contains(";") || v.contains(",") ? "\"\(v)\"" : v
        }
        let head = "grupo;nombre;host;usuario;puerto;salto;descripcion;tipo"
        return ([head] + sessions.map { s in
            [s.group, s.name, s.host, s.user, s.port, s.jump, s.summary, s.kind.annotation].map(cell).joined(separator: ";")
        }).joined(separator: "\n") + "\n"
    }

    /// Lo que importa `SessionImporter` de un JSON exportado (nil si no es uno de estos).
    static func found(_ text: String) -> [SessionImporter.Found]? {
        guard let doc = try? JSONDecoder().decode(Document.self, from: Data(text.utf8)), doc.formato == format else { return nil }
        return doc.sesiones.map { e in
            var f = SessionImporter.Found(group: e.grupo, original: e.nombre, host: e.equipo ?? "", user: e.usuario ?? "",
                                          port: e.puerto.flatMap { $0.isEmpty ? nil : $0 } ?? "22", jump: e.salto ?? "",
                                          ref: e.nombre, summary: e.descripcion ?? "")
            f.kind = SessionProfile.Transport(annotation: e.tipo) ?? .ssh
            f.keyFile = e.claveFile ?? ""
            f.legacy = e.antiguo ?? false
            f.serial = e.serie.flatMap(SerialLine.init(annotation:))
            f.notes = e.notas ?? []
            f.extra = e.opciones ?? []
            return f
        }
    }
}
