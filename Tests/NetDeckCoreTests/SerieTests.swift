import Foundation
import Darwin
import Testing
@testable import NetDeckCore

/// Consola serie: la trama se valida antes de abrir y se aplica de verdad con termios (aquí sobre un pseudoterminal:
/// nada de dispositivos reales), comprobada con tcgetattr. En serie: varias pruebas reutilizan a propósito el número de
/// descriptor de un puerto cerrado (dup2) desde el mismo número fijo; en paralelo, otra podía quedarse con ese número
/// justo entre el cierre y el dup2 y escribir en la tubería de ésta.
@Suite(.serialized) struct SerieTests {
    /// Un pseudoterminal (maestro, esclavo); se cierra al acabar.
    private func withPTY(_ body: (Int32) throws -> Void) throws {
        var m: Int32 = -1, s: Int32 = -1
        try #require(openpty(&m, &s, nil, nil, nil) == 0)
        defer { close(m); close(s) }
        try body(s)
    }

    private func attrs(_ fd: Int32) throws -> termios {
        var t = termios()
        try #require(tcgetattr(fd, &t) == 0)
        return t
    }

    @Test func tramasValidasEInvalidas() {
        #expect(SerialLine.parseFrame("8N1")! == (8, .none, 1))
        #expect(SerialLine.parseFrame("7e2")! == (7, .even, 2))
        #expect(SerialLine.parseFrame("5O1")! == (5, .odd, 1))
        for bad in ["", "8N", "8N10", "9N1", "4N1", "8X1", "8N3", "8N0", "N81", "８N1", "8 N1"] {
            #expect(SerialLine.parseFrame(bad) == nil, "\(bad)")
        }
        let l = SerialLine(annotation: "/dev/cu.usbserial-0001 115200 6O2")
        #expect(l == SerialLine(device: "/dev/cu.usbserial-0001", speed: 115200, dataBits: 6, parity: .odd, stopBits: 2))
        #expect(l?.annotation == "/dev/cu.usbserial-0001 115200 6O2")
    }

    @Test func problemasAntesDeAbrir() {
        #expect(SerialLine(device: "/dev/cu.usbserial-0001").problem == nil)
        for dev in ["", "/dev/disk0", "/dev/ttys003", "/tmp/cu.a", "/dev/cu.a;b", "/dev/cu.../x", "-o/dev/cu.a"] {
            #expect(SerialLine(device: dev).problem?.contains("/dev/cu.*") == true, "\(dev)")
        }
        #expect(SerialLine(device: "/dev/cu.a", speed: 12345).problem?.contains("12345") == true)
        #expect(SerialLine(device: "/dev/cu.a", dataBits: 9).problem?.contains("9N1") == true)
        #expect(SerialLine(device: "/dev/cu.a", stopBits: 3).problem?.contains("8N3") == true)
        // (y la pestaña no llega a abrir nada)
        let r = ConnectionRoute.serial(SerialLine(device: "/dev/cu.a", speed: 1200), title: "c")
        #expect(r.launchProblem { _ in true }?.contains("1200") == true)
    }

    @Test func aplicaCadaTramaAlPuerto() throws {
        let casos = [SerialLine(device: "/dev/cu.x", speed: 9600, dataBits: 8, parity: .none, stopBits: 1),
                     SerialLine(device: "/dev/cu.x", speed: 115200, dataBits: 7, parity: .even, stopBits: 2),
                     SerialLine(device: "/dev/cu.x", speed: 19200, dataBits: 6, parity: .odd, stopBits: 1),
                     SerialLine(device: "/dev/cu.x", speed: 57600, dataBits: 5, parity: .odd, stopBits: 2)]
        let sizes = [8: CS8, 7: CS7, 6: CS6, 5: CS5]
        try withPTY { fd in
            for l in casos {
                // (lo que hubiera antes no debe quedarse: control de flujo encendido, paridad, 2 bits de parada)
                var dirty = try attrs(fd)
                dirty.c_cflag |= tcflag_t(CRTSCTS | PARENB | PARODD | CSTOPB)
                dirty.c_iflag |= tcflag_t(IXON | IXOFF)
                tcsetattr(fd, TCSANOW, &dirty)

                try SerialPort.configure(fd: fd, line: l)
                var t = try attrs(fd)
                #expect(cfgetispeed(&t) == speed_t(l.speed) && cfgetospeed(&t) == speed_t(l.speed), "\(l.frame)")
                #expect(t.c_cflag & tcflag_t(CSIZE) == tcflag_t(sizes[l.dataBits]!), "\(l.frame)")
                #expect((t.c_cflag & tcflag_t(PARENB) != 0) == (l.parity != .none), "\(l.frame)")
                #expect((t.c_cflag & tcflag_t(PARODD) != 0) == (l.parity == .odd), "\(l.frame)")
                #expect((t.c_cflag & tcflag_t(CSTOPB) != 0) == (l.stopBits == 2), "\(l.frame)")
                #expect(t.c_cflag & tcflag_t(CRTSCTS) == 0 && t.c_iflag & tcflag_t(IXON | IXOFF | IXANY) == 0)
                #expect(t.c_cflag & tcflag_t(CLOCAL | CREAD) == tcflag_t(CLOCAL | CREAD))
                #expect(SerialPort.mismatches(l, t).isEmpty)
            }
        }
    }

    @Test func loQueElPuertoNoCogeSeDice() throws {
        let l = SerialLine(device: "/dev/cu.x", speed: 115200, dataBits: 7, parity: .even, stopBits: 2)
        try withPTY { fd in
            try SerialPort.configure(fd: fd, line: l)
            let ok = try attrs(fd)
            // (como si el dispositivo hubiera dejado otra velocidad, 8 bits, sin paridad, 1 de parada y RTS/CTS)
            var t = ok
            cfsetspeed(&t, speed_t(9600))
            #expect(SerialPort.mismatches(l, t) == [L("velocidad \(String(115200)) (queda \(String(9600)))")])
            t = ok
            t.c_cflag = (t.c_cflag & ~tcflag_t(CSIZE)) | tcflag_t(CS8)
            #expect(SerialPort.mismatches(l, t) == [L("\(String(7)) bits de datos")])
            t = ok
            t.c_cflag |= tcflag_t(PARODD)
            #expect(SerialPort.mismatches(l, t) == [L("paridad \("E")")])
            t = ok
            t.c_cflag &= ~tcflag_t(CSTOPB)
            #expect(SerialPort.mismatches(l, t) == [L("\(String(2)) bits de parada")])
            t = ok
            t.c_cflag |= tcflag_t(CRTSCTS)
            #expect(SerialPort.mismatches(l, t) == [L("sin control de flujo")])
        }
    }

    @Test func unaVelocidadOUnDescriptorNoAceptadosDanError() throws {
        // (una velocidad fuera de la lista no llega a tocar el puerto)
        try withPTY { fd in
            let before = try attrs(fd)
            #expect(throws: SerialPort.Failure.self) {
                try SerialPort.configure(fd: fd, line: SerialLine(device: "/dev/cu.x", speed: 12345))
            }
            var after = try attrs(fd)
            var b = before
            #expect(cfgetospeed(&after) == cfgetospeed(&b) && after.c_cflag == before.c_cflag)
        }
        // (algo que no es un terminal: tcgetattr/tcsetattr fallan y se dice, no se sigue en silencio)
        var p: [Int32] = [-1, -1]
        try #require(pipe(&p) == 0)
        defer { close(p[0]); close(p[1]) }
        do {
            try SerialPort.configure(fd: p[0], line: SerialLine(device: "/dev/cu.x"))
            Issue.record("una tubería no es un puerto serie")
        } catch let e as SerialPort.Failure {
            #expect(!e.message.isEmpty && e.errorDescription == e.message)
        }
        // (y un puerto que no existe no se abre)
        #expect(throws: SerialPort.Failure.self) {
            _ = try SerialPort(SerialLine(device: "/dev/cu.netdeck-no-existe"), queue: .main, onData: { _ in }, onClose: { _ in })
        }
    }

    // MARK: - Escritura y cierre con el búfer del PTY lleno

    private func withPTYPair(_ body: (Int32, Int32) throws -> Void) throws {
        var m: Int32 = -1, s: Int32 = -1
        try #require(openpty(&m, &s, nil, nil, nil) == 0)
        defer { close(m); close(s) }
        try #require(fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK) == 0)
        try body(m, s)
    }

    private func port(_ slave: Int32, _ observed: SerialObservation) throws -> (SerialPort, Int32) {
        var owned: Int32 = -1
        let port = try SerialPort(SerialLine(device: "/dev/cu.prueba"), queue: DispatchQueue(label: "serie.prueba"),
                                  openDevice: { _, flags in
            #expect(flags & O_NONBLOCK != 0)
            // (número alto para reciclarlo sin pisar los archivos que abran otros tests en paralelo)
            owned = fcntl(slave, F_DUPFD_CLOEXEC, max(0, min(512, getdtablesize() - 16)))
            return owned
        }, onData: { observed.receive($0) }, onClose: { observed.fail($0) })
        return (port, owned)
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        repeat {
            if condition() { return true }
            usleep(1000)
        } while DispatchTime.now().uptimeNanoseconds < deadline
        return false
    }

    private func available(_ fd: Int32) -> [UInt8] {
        var result: [UInt8] = [], buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 { result.append(contentsOf: buf[..<n]) }
            else if n < 0, errno == EINTR { continue }
            else { return result }
        }
    }

    private func saturated(_ fd: Int32) -> Bool {
        var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        return poll(&p, 1, 0) == 0
    }

    @Test func escrituraNoBloqueanteConservaTodoYElOrden() throws {
        try withPTYPair { master, slave in
            let observed = SerialObservation()
            let (port, fd) = try self.port(slave, observed)
            defer { port.close() }
            #expect(fcntl(fd, F_GETFL) & O_NONBLOCK != 0)
            let first = [UInt8](repeating: 65, count: 1024 * 1024), last = Array("fin\r\n".utf8)
            port.write(first[...]); port.write(last[...])
            var received: [UInt8] = []
            #expect(waitUntil {
                received.append(contentsOf: available(master))
                return received.count >= first.count + last.count
            })
            #expect(received == first + last)
            let banner = Array("consola\r\n".utf8)
            #expect(banner.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) } == banner.count)
            #expect(waitUntil { observed.data == banner })
            #expect(observed.errors.isEmpty)
        }
    }

    @Test func cerrarUnPegadoSaturadoDescartaPendientesYLiberaElPuerto() throws {
        try withPTYPair { master, slave in
            let observed = SerialObservation()
            let (port, fd) = try self.port(slave, observed)
            defer { port.close() }
            port.write([UInt8](repeating: 65, count: 4 * 1024 * 1024)[...])
            port.write(Array("NO DEBE SALIR".utf8)[...])
            try #require(waitUntil { saturated(fd) })      // (nadie lee el maestro: el write de antes se bloquearía)
            port.close(); port.close()
            try #require(waitUntil { fcntl(fd, F_GETFD) == -1 && errno == EBADF })
            // (TIOCEXCL no debe sobrevivir aunque el test aún conserve el descriptor original del PTY)
            let path = String(cString: try #require(ttyname(slave)))
            let reopened = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            #expect(reopened >= 0)
            if reopened >= 0 { close(reopened) }
            #expect(!available(master).contains(78))        // (N de «NO DEBE SALIR»: sólo podría llegar tras el pegado)

            // (el número del puerto ahora es una tubería; ni las tareas antiguas ni nuevas pueden escribir en ella)
            var pipes: [Int32] = [-1, -1]
            try #require(pipe(&pipes) == 0)
            defer { close(pipes[0]); close(pipes[1]) }
            try #require(dup2(pipes[1], fd) == fd)
            defer { close(fd) }
            try #require(fcntl(pipes[0], F_SETFL, O_NONBLOCK) == 0)
            DispatchQueue.concurrentPerform(iterations: 64) { _ in port.write([66][...]); port.sendBreak() }
            usleep(350_000)
            #expect(available(pipes[0]).isEmpty)
            #expect(observed.errors.isEmpty)                // (close explícito no dispara onClose)
        }
    }

    @Test func soltarUnPuertoSaturadoTambienCierraElDescriptor() throws {
        try withPTYPair { _, slave in
            let observed = SerialObservation()
            var port: SerialPort?, fd: Int32
            (port, fd) = try self.port(slave, observed)
            port?.write([UInt8](repeating: 65, count: 4 * 1024 * 1024)[...])
            try #require(waitUntil { saturated(fd) })
            port = nil
            #expect(waitUntil { fcntl(fd, F_GETFD) == -1 && errno == EBADF })
            #expect(observed.errors.isEmpty)
        }
    }

    @Test func breakNativoPermiteCerrarAntesDeLos250ms() throws {
        try withPTYPair { master, slave in
            let observed = SerialObservation()
            let (port, fd) = try self.port(slave, observed)
            defer { port.close() }
            port.sendBreak()
            port.write([65][...])
            try #require(waitUntil { available(master) == [65] })
            #expect(observed.errors.isEmpty)
            port.close()
            try #require(waitUntil { fcntl(fd, F_GETFD) == -1 && errno == EBADF })
            let recycled = Darwin.open("/dev/null", O_WRONLY)
            try #require(recycled >= 0)
            defer { close(recycled) }
            try #require(dup2(recycled, fd) == fd)
            defer { close(fd) }
            usleep(350_000)                                 // (ya habría vencido el apagado de BREAK)
            #expect(observed.errors.isEmpty)
            #expect(fcntl(fd, F_GETFD) != -1)
        }
    }
}

private final class SerialObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []
    private var failures: [String] = []
    var data: [UInt8] { lock.withLock { bytes } }
    var errors: [String] { lock.withLock { failures } }
    func receive(_ data: ArraySlice<UInt8>) { lock.withLock { bytes.append(contentsOf: data) } }
    func fail(_ reason: String) { lock.withLock { failures.append(reason) } }
}

/// El puerto no se hereda: una shell local abierta después (otra pestaña) no puede quedarse con el dispositivo. Se pide
/// O_CLOEXEC al abrir y se asegura FD_CLOEXEC aunque quien lo abra no lo ponga.
@Suite struct SerieSinHerenciaTests {
    @Test func elPuertoNoPasaAOtrosProcesos() throws {
        var m: Int32 = -1, s: Int32 = -1
        try #require(openpty(&m, &s, nil, nil, nil) == 0)
        defer { close(m); close(s) }
        var asked: Int32 = 0, owned: Int32 = -1
        let port = try SerialPort(SerialLine(device: "/dev/cu.prueba"), queue: DispatchQueue(label: "serie.herencia"),
                                  openDevice: { _, flags in
            asked = flags
            owned = fcntl(s, F_DUPFD, 0)                    // (sin CLOEXEC, como un open sin ella; el primero libre)
            return owned
        }, onData: { _ in }, onClose: { _ in })
        defer { port.close() }
        #expect(asked & O_CLOEXEC != 0)
        #expect(owned >= 0 && fcntl(owned, F_GETFD) & FD_CLOEXEC != 0)
    }
}
