import AppKit
import CoreText
import Testing
@testable import NetDeckCore

@Suite struct TerminalFontTests {
    static let text = "flaps filas office ffl -> != =="

    /// Con ligaduras, «fl»/«fi»/«ffl» salen en un glifo (y SwiftTerm correría la línea); sin ellas, uno por carácter,
    /// también en la negrita y la cursiva que saca SwiftTerm de la normal. (Hoefler Text: viene con macOS y las tiene.)
    @Test(.enabled(if: NSFont(name: "Hoefler Text", size: 13) != nil))
    func sinLigaduras() throws {
        let f = try #require(NSFontManager.shared.font(withFamily: "Hoefler Text", traits: [], weight: 5, size: 13))
        #expect(TerminalFont.glyphCount(f, Self.text) < Self.text.utf16.count)
        let strict = TerminalFont.strict(f) as NSFont
        #expect(strict.pointSize == f.pointSize && strict.familyName == f.familyName)
        #expect(TerminalFont.glyphCount(strict, Self.text) == Self.text.utf16.count)
        let bold = NSFontManager.shared.convert(strict, toHaveTrait: .boldFontMask)
        #expect(TerminalFont.glyphCount(bold, Self.text) == Self.text.utf16.count)
    }

    /// La del sistema (la de por defecto) también: un glifo por carácter.
    @Test func laDelSistema() {
        let f = TerminalFont.strict(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(TerminalFont.glyphCount(f, Self.text) == Self.text.utf16.count)
    }
}
