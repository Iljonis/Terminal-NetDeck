import Foundation
import Testing
@testable import NetDeckCore

@Suite struct ButtonTests {
    static let text = """
        # mis botones
        #  Formato: Grupo :: modo :: Nombre :: comando

        Juniper   :: type :: Match            :: show conf | display set | match
        Juniper   :: run  :: RX ópticos [F5]  :: show int diagnostics optics ;; show chassis alarms
        Huawei    :: run  :: Int desc [S-F6]  :: dis int desc | e {{filtro=down}} {{interfaz}} {{filtro}}
        Huawei    :: pass :: AD               :: AD ES
        Mal       :: nada :: x                :: y
        Huawei    :: run  :: Otra [F5]        :: display version
        sin formato
        """

    @Test func leeComoNetDeck() {
        let f = ButtonFile(text: Self.text)
        #expect(f.header == ["# mis botones", "#  Formato: Grupo :: modo :: Nombre :: comando"])
        #expect(f.buttons.map(\.name) == ["Match", "RX ópticos", "Int desc", "AD", "Otra"])
        #expect(f.groups == ["Juniper", "Huawei"])
        #expect(f.buttons[0].command == "show conf | display set | match")
        #expect(f.buttons[1].lines == ["show int diagnostics optics", "show chassis alarms"])
        #expect(f.button(forKey: "F5")?.name == "RX ópticos")
        #expect(f.buttons[4].hotkey == nil)                    // la F5 ya era de otro
        #expect(f.problems.count == 3)
    }

    @Test func huecos() {
        let b = ButtonFile(text: Self.text).buttons[2]
        #expect(b.holes.map(\.name) == ["filtro", "interfaz"])
        #expect(b.holes.first?.value == "down")
        #expect(b.filled(["interfaz": "GE0/0/1"]) == "dis int desc | e down GE0/0/1 down")
    }

    @Test func escribirYLeer() {
        let f = ButtonFile(text: Self.text)
        let again = ButtonFile(text: f.render())
        #expect(again.buttons == f.buttons)
        #expect(again.header == f.header)
    }

    @Test func teclasDeFuncion() {
        func k(_ s: String) -> String? { FunctionKey.name(Array(s.utf8)) }
        #expect(k("\u{1b}OP") == "F1")
        #expect(k("\u{1b}[15~") == "F5")
        #expect(k("\u{1b}[17;2~") == "S-F6")
        #expect(k("\u{1b}[1;5Q") == "C-F2")
        #expect(k("\u{1b}[24;3~") == "M-F12")
        #expect(k("\u{1b}[A") == nil)
    }
}
