import Foundation

/// Grupos con «/» como carpetas dentro de carpetas («Clientes/Madrid/Core»). Un grupo sin «/» es una carpeta sola,
/// como siempre. Dentro de cada carpeta van primero sus sesiones y luego sus subcarpetas, en orden de aparición.
public enum GroupTree {
    public enum Row<Item> {
        /// `path`: la ruta entera («Clientes/Madrid»); `name`: el último trozo; `count`: sesiones de dentro (todas).
        case folder(path: String, name: String, depth: Int, count: Int)
        case item(Item, depth: Int)
    }

    /// «Clientes / Madrid//Core» → ["Clientes", "Madrid", "Core"].
    public static func components(_ group: String) -> [String] {
        group.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// El grupo está en la carpeta `path` (es ella o una de sus subcarpetas).
    public static func contains(_ path: String, _ group: String) -> Bool {
        let p = components(path), g = components(group)
        return !p.isEmpty && g.count >= p.count && Array(g.prefix(p.count)) == p
    }

    private final class Node<Item> {
        let name: String, path: String
        var items: [Item] = []
        var children: [Node] = []
        init(name: String, path: String) { self.name = name; self.path = path }
        var count: Int { items.count + children.reduce(0) { $0 + $1.count } }

        func child(_ n: String) -> Node {
            if let c = children.first(where: { $0.name == n }) { return c }
            let c = Node(name: n, path: path.isEmpty ? n : "\(path)/\(n)")
            children.append(c)
            return c
        }
    }

    /// Filas a pintar: carpetas y sesiones con su sangría; lo de dentro de una carpeta plegada no sale.
    public static func rows<Item>(_ groups: [(name: String, items: [Item])], collapsed: Set<String> = []) -> [Row<Item>] {
        let root = Node<Item>(name: "", path: "")
        for g in groups {
            var n = root
            for c in components(g.name).isEmpty ? [g.name] : components(g.name) { n = n.child(c) }
            n.items += g.items
        }
        var out: [Row<Item>] = []
        func walk(_ n: Node<Item>, _ depth: Int) {
            out.append(.folder(path: n.path, name: n.name, depth: depth, count: n.count))
            guard !collapsed.contains(n.path) else { return }
            out += n.items.map { .item($0, depth: depth + 1) }
            n.children.forEach { walk($0, depth + 1) }
        }
        root.children.forEach { walk($0, 0) }
        return out
    }
}
