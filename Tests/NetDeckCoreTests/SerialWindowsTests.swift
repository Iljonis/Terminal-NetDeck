#if os(Windows)
import Testing
import Foundation
import WinSDK
@testable import NetDeckCore

/// `SerialLine` y la trama de `SerialPort` en Windows, sin abrir hardware.
@Suite struct SerialWindowsTests {
    @Test func aceptaCOMn() {
        #expect(SerialLine.isValidDevice("COM1"))
        #expect(SerialLine.isValidDevice("COM3"))
        #expect(SerialLine.isValidDevice("COM15"))
        #expect(SerialLine.isValidDevice("com7"))
        #expect(!SerialLine.isValidDevice("COM0"))
        #expect(!SerialLine.isValidDevice("COM"))
        #expect(!SerialLine.isValidDevice("COM01"))
        for malo in ["COM3;x", "COM3 ", #"\\.\COM3"#, "COM3:", "LPT1", "-COM3", "COM3..", ""] {
            #expect(!SerialLine.isValidDevice(malo), "\(malo)")
        }
        // (un archivo de sesiones escrito en el Mac se sigue leyendo: la ruta vale como texto)
        #expect(SerialLine.isValidDevice("/dev/cu.usbserial-0001"))
    }

    @Test func deviceForOpenAnteponeElPrefijo() {
        #expect(SerialLine(device: "COM3").deviceForOpen == #"\\.\COM3"#)
        #expect(SerialLine(device: "COM15").deviceForOpen == #"\\.\COM15"#)
        #expect(SerialLine(device: "com7").deviceForOpen == #"\\.\COM7"#)
        #expect(SerialLine(device: "/dev/cu.x").deviceForOpen == "/dev/cu.x")
    }

    @Test func problemParaCOM0() {
        let linea = SerialLine(device: "COM0")
        #expect(linea.problem == L("Puerto serie no válido: «\("COM0")» (sólo COMn)"))
        #expect(!linea.isValid)
    }

    @Test func serialLineTrama() {
        let linea = SerialLine(device: "COM1", speed: 9600, dataBits: 8, parity: .none, stopBits: 1)
        #expect(linea.isValid)
        #expect(linea.frame == "8N1")
        #expect(SerialLine(annotation: "COM4 115200 7E2")
                == SerialLine(device: "COM4", speed: 115200, dataBits: 7, parity: .even, stopBits: 2))
        #expect(SerialLine(annotation: "COM4 9600 9N1") == nil)
    }

    @Test func tramaDelDCB() {
        var dcb = DCB()
        dcb.BaudRate = 9600; dcb.ByteSize = 8; dcb.Parity = 0; dcb.StopBits = 0
        #expect(SerialPort.mismatches(SerialLine(device: "COM1"), dcb).isEmpty)
        #expect(SerialPort.mismatches(SerialLine(device: "COM1", speed: 115200), dcb)
                == [L("velocidad \(String(115200)) (queda \(String(9600)))")])
        #expect(SerialPort.mismatches(SerialLine(device: "COM1", dataBits: 7, parity: .even, stopBits: 2), dcb)
                == [L("\(String(7)) bits de datos"), L("paridad \("E")"), L("\(String(2)) bits de parada")])
        dcb.fOutxCtsFlow = 1
        #expect(SerialPort.mismatches(SerialLine(device: "COM1"), dcb) == [L("sin control de flujo")])
    }

    @Test func noAbreLoQueNoExisteNiLoQueNoEsUnPuerto() {
        // (COM250 no existe en ninguna máquina de pruebas; el motivo es el de Windows, no se comprueba el texto)
        #expect(throws: SerialPort.Failure.self) {
            _ = try SerialPort(SerialLine(device: "COM250"), queue: .main, onData: { _ in }, onClose: { _ in })
        }
        #expect(throws: SerialPort.Failure.self) {
            _ = try SerialPort(SerialLine(device: "COM0"), queue: .main, onData: { _ in }, onClose: { _ in })
        }
    }

    @Test func devicesDevuelvePortosValidos() {
        // La máquina de tests puede no tener puertos serie: lo importante es que el array está bien formado.
        let result = SerialLine.devices()
        for d in result {
            #expect(SerialLine.isValidDevice(d), "devices() devolvió un dispositivo inválido: \(d)")
        }
    }
}
#endif