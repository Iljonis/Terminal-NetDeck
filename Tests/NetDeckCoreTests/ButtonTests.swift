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

    static let tres = ButtonFile(text: """
        A :: run :: a1 :: x
        B :: run :: b1 :: y
        A :: run :: a2 :: z
        C :: type :: c1 [F2] :: w
        """)

    @Test func categoriasEnBloques() {
        var f = Self.tres
        f.compactGroups()
        #expect(f.buttons.map(\.name) == ["a1", "a2", "b1", "c1"])
        let r1 = f.addGroup("D")
        #expect(r1 != nil)
        let r11 = f.addGroup("A")
        #expect(r11 == nil)                         // ya está
        let r12 = f.addGroup("x :: y")
        #expect(r12 == nil)                    // rompería el formato
        #expect(f.groups == ["A", "B", "C", "D"])
    }

    @Test func renombrarYJuntar() {
        var f = Self.tres
        let r2 = f.renameGroup("B", to: "Cisco")
        #expect(r2)
        #expect(f.groups == ["A", "Cisco", "C"])
        let r13 = f.renameGroup("C", to: "A")
        #expect(r13)                    // se junta con A
        #expect(f.groups == ["A", "Cisco"])
        #expect(f.buttons.map(\.name) == ["a1", "a2", "c1", "b1"])
        let r3 = f.renameGroup("A", to: "")
        #expect(!r3)
        #expect(ButtonFile(text: f.render()).buttons == f.buttons)
    }

    @Test func borrarOMoverCategoria() {
        var f = Self.tres
        f.removeGroup("A", movingTo: "C")
        #expect(f.groups == ["B", "C"])
        #expect(f.buttons.map(\.name) == ["b1", "c1", "a1", "a2"])
        f.removeGroup("C")
        #expect(f.buttons.map(\.name) == ["b1"])
    }

    @Test func ordenarCategorias() {
        var f = Self.tres
        let r4 = f.moveGroup("C", by: -1)
        #expect(r4)
        #expect(f.groups == ["A", "C", "B"])
        #expect(f.buttons.map(\.name) == ["a1", "a2", "c1", "b1"])
        let r5 = f.moveGroup("A", by: -1)
        #expect(!r5)
        let r6 = f.moveGroup("A", by: 1)
        #expect(r6)
        #expect(f.groups == ["C", "A", "B"])
    }

    @Test func botonesDentroYEntreCategorias() {
        var f = Self.tres
        let a2 = f.buttons[2].id
        let r14 = f.moveButton(a2, by: -1)
        #expect(r14)                       // salta el de B
        #expect(f.buttons.map(\.name) == ["a2", "a1", "b1", "c1"])
        let r15 = f.moveButton(a2, by: -1)
        #expect(!r15)                      // ya es el primero de A
        let r7 = f.moveButton(a2, toGroup: "C")
        #expect(r7)
        #expect(f.buttons.last?.name == "a2" && f.buttons.last?.group == "C")
        let c1 = f.buttons.first { $0.name == "c1" }!.id
        let copy = f.duplicateButton(c1)
        let i = f.buttons.firstIndex { $0.id == c1 }!
        #expect(f.buttons[i + 1].id == copy)
        #expect(f.buttons[i + 1].name == "c1 2" && f.buttons[i + 1].hotkey == nil && f.buttons[i + 1].command == "w")
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
