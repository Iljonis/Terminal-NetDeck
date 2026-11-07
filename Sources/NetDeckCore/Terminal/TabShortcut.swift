/// ⌘1…⌘9 (menú Terminal → «Ir a la pestaña»): de ⌘1 a ⌘8, la pestaña de ese número en la barra; ⌘9, la última, como
/// en Safari o en Terminal.
public enum TabShortcut {
    /// El índice en la barra, o nil si no hay tantas pestañas.
    public static func index(_ n: Int, count: Int) -> Int? {
        guard (1...9).contains(n), count > 0 else { return nil }
        let i = n == 9 ? count - 1 : n - 1
        return i < count ? i : nil
    }
}
