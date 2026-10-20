import Foundation
import Darwin

/// Consola serie sin programas externos: termios aplica y comprueba la trama. Las lecturas van a `queue`; las
/// escrituras no bloqueantes esperan disponibilidad sin retener la cola. El cierre cancela ambos eventos antes de
/// liberar el descriptor (ningún evento pendiente puede escribir en otro archivo que recicle su número).
public final class SerialPort: @unchecked Sendable {
    /// Por qué no se abre o no se configura (el texto, ya traducido, va a la pestaña y al aviso).
    public struct Failure: Error, LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    private let fd: Int32
    private let source: DispatchSourceRead
    private let output: DispatchSourceWrite
    private let writer = DispatchQueue(label: "netdeck.serie.escritura")
    private let queue: DispatchQueue
    private let onClose: @Sendable (String) -> Void
    private let lock = NSLock()
    private var closed = false
    private var suspended = true     // (output: protegido por lock, también al cancelar)
    private var pending: [ArraySlice<UInt8>] = []     // (sólo en writer)
    private var breakGeneration = 0

    /// Abre `line.device`, aplica y comprueba la trama y empieza a leer. `onClose`: el puerto se ha cerrado solo
    /// (adaptador desenchufado, error de lectura o escritura), con el motivo; no se llama si lo cierra `close()`.
    public convenience init(_ line: SerialLine, queue: DispatchQueue,
                            onData: @escaping @Sendable (ArraySlice<UInt8>) -> Void,
                            onClose: @escaping @Sendable (String) -> Void) throws {
        try self.init(line, queue: queue, openDevice: { Darwin.open($0, $1) }, onData: onData, onClose: onClose)
    }

    /// Apertura inyectable sólo para probar con PTY, sin relajar la regla pública /dev/cu.* o /dev/tty.*.
    init(_ line: SerialLine, queue: DispatchQueue, openDevice: (String, Int32) -> Int32,
         onData: @escaping @Sendable (ArraySlice<UInt8>) -> Void,
         onClose: @escaping @Sendable (String) -> Void) throws {
        if let p = line.problem { throw Failure(message: p) }
        // (O_CLOEXEC: una shell local abierta después no hereda el dispositivo)
        let fd = openDevice(line.device, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(errno))")) }
        do {
            // (y FD_CLOEXEC asegurado aunque quien lo abra no lo haya puesto)
            let fdFlags = fcntl(fd, F_GETFD)
            guard fdFlags >= 0, fcntl(fd, F_SETFD, fdFlags | FD_CLOEXEC) == 0 else {
                throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(errno))")) }
            if ioctl(fd, Self.exclusive) != 0 { throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(errno))")) }
            try Self.configure(fd: fd, line: line)
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(errno))")) }
        } catch {
            _ = ioctl(fd, Self.notExclusive)
            Darwin.close(fd)
            throw error
        }
        self.fd = fd
        self.queue = queue
        self.onClose = onClose
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        output = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: writer)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 8192)
            let result: (Int, Int32)? = self.lock.withLock {
                guard !self.closed else { return nil }
                let n = Darwin.read(fd, &buf, buf.count)
                return (n, errno)
            }
            guard let (n, code) = result else { return }
            if n > 0 { onData(buf[..<n]); return }
            if n < 0, code == EINTR || code == EAGAIN { return }
            self.fail(n == 0 ? L("el puerto se ha cerrado") : Self.why(code))
        }
        output.setEventHandler { [weak self] in self?.drain() }
        // (los dos manejadores deben haber terminado: cerrar desde uno solo permitiría reutilizar el fd en el otro)
        let cancelled = DispatchGroup()
        cancelled.enter(); cancelled.enter()
        source.setCancelHandler { cancelled.leave() }
        output.setCancelHandler { cancelled.leave() }
        cancelled.notify(queue: writer) {
            _ = ioctl(fd, Self.clearBreak)
            tcflush(fd, TCOFLUSH)             // (descartar también lo que el controlador aún no ha transmitido)
            _ = ioctl(fd, Self.notExclusive)
            Darwin.close(fd)
        }
        source.resume()
    }

    deinit { _ = finish() }

    /// Lo que se teclea o se pega, tal cual. Si se llena la salida, se espera al siguiente evento de disponibilidad.
    public func write(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty, !isClosed else { return }
        let data = Array(bytes)[...]
        writer.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.pending.append(data)
            self.lock.withLock {
                if !self.closed, self.suspended { self.suspended = false; self.output.resume() }
            }
        }
    }

    private func drain() {
        // (turnos acotados: ni un pegado grande ni una sucesión de EINTR retrasan el cierre o BREAK)
        for _ in 0..<16 {
            guard !pending.isEmpty else { break }
            let result: (Int, Int32)? = lock.withLock {
                guard !closed else { return nil }
                let n = pending[0].prefix(4096).withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                return (n, errno)
            }
            guard let (n, code) = result else { pending.removeAll(); return }
            if n < 0, code == EINTR { continue }
            if n < 0, code == EAGAIN || code == EWOULDBLOCK { return }
            if n <= 0 { fail(L("No se puede escribir en el puerto: \(Self.why(n == 0 ? EIO : code))")); return }
            pending[0] = pending[0].dropFirst(n)
            if pending[0].isEmpty { pending.removeFirst() }
        }
        lock.withLock {
            if !closed, pending.isEmpty, !suspended { suspended = true; output.suspend() }
        }
    }

    /// BREAK nativo durante 250 ms (sin procesos externos ni una espera que retenga el cierre).
    public func sendBreak() {
        writer.async { [weak self] in
            guard let self else { return }
            let code: Int32? = self.lock.withLock {
                guard !self.closed else { return nil }
                return ioctl(self.fd, Self.setBreak) == 0 ? 0 : errno
            }
            guard let code else { return }
            if code != 0 { self.fail(L("No se puede enviar BREAK: \(Self.why(code))")); return }
            self.breakGeneration += 1
            let generation = self.breakGeneration
            self.writer.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                guard let self else { return }
                let code: Int32? = self.lock.withLock {
                    guard !self.closed, self.breakGeneration == generation else { return nil }
                    return ioctl(self.fd, Self.clearBreak) == 0 ? 0 : errno
                }
                if let code, code != 0 { self.fail(L("No se puede enviar BREAK: \(Self.why(code))")) }
            }
        }
    }

    public func close() { _ = finish() }

    private var isClosed: Bool { lock.withLock { closed } }

    private func fail(_ reason: String) {
        if finish() { let onClose = onClose; queue.async { onClose(reason) } }
    }

    /// true la primera vez. El lock excluye cada syscall: al volver de close no empieza otra escritura ni BREAK.
    private func finish() -> Bool {
        let first = lock.withLock { () -> Bool in
            if closed { return false }
            closed = true
            source.cancel()
            output.cancel()
            if suspended { suspended = false; output.resume() }
            return true
        }
        if first { writer.async { [weak self] in self?.pending.removeAll() } }
        return first
    }

    // MARK: - termios

    /// TIOCEXCL = _IO('t', 13) (las macros _IO no llegan a Swift).
    static let exclusive: UInt = 0x2000_740D
    private static let notExclusive: UInt = 0x2000_740E
    private static let setBreak: UInt = 0x2000_747B
    private static let clearBreak: UInt = 0x2000_747A

    /// Aplica la trama de `line` a `fd` (modo crudo, CLOCAL|CREAD) y la relee: si el dispositivo no acepta algún valor
    /// (velocidad, bits, paridad, parada o el control de flujo apagado), error con lo que no ha cogido.
    public static func configure(fd: Int32, line: SerialLine) throws {
        if let p = line.problem { throw Failure(message: p) }
        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { throw Failure(message: L("El puerto no admite configuración: \(why(errno))")) }
        cfmakeraw(&t)
        t.c_cflag &= ~tcflag_t(CSIZE | PARENB | PARODD | CSTOPB | CRTSCTS)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD) | size(line.dataBits)
        if line.parity != .none { t.c_cflag |= tcflag_t(PARENB) }
        if line.parity == .odd { t.c_cflag |= tcflag_t(PARODD) }
        if line.stopBits == 2 { t.c_cflag |= tcflag_t(CSTOPB) }
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        guard cfsetspeed(&t, speed_t(line.speed)) == 0 else {
            throw Failure(message: L("El puerto no admite la velocidad \(String(line.speed))"))
        }
        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            throw Failure(message: L("El puerto no acepta \(String(line.speed)) \(line.frame): \(why(errno))"))
        }
        var got = termios()
        guard tcgetattr(fd, &got) == 0 else { throw Failure(message: L("El puerto no admite configuración: \(why(errno))")) }
        let bad = mismatches(line, got)
        if !bad.isEmpty { throw Failure(message: L("El puerto no ha aceptado: \(bad.joined(separator: ", "))")) }
    }

    /// Lo que de `line` no está en `t` (vacío: todo aplicado).
    public static func mismatches(_ line: SerialLine, _ t: termios) -> [String] {
        var t = t
        var bad: [String] = []
        let (i, o) = (Int(cfgetispeed(&t)), Int(cfgetospeed(&t)))
        if i != line.speed || o != line.speed { bad.append(L("velocidad \(String(line.speed)) (queda \(String(o)))")) }
        if t.c_cflag & tcflag_t(CSIZE) != size(line.dataBits) { bad.append(L("\(String(line.dataBits)) bits de datos")) }
        let parity: SerialLine.Parity = t.c_cflag & tcflag_t(PARENB) == 0 ? .none : t.c_cflag & tcflag_t(PARODD) == 0 ? .even : .odd
        if parity != line.parity { bad.append(L("paridad \(line.parity.rawValue)")) }
        if (t.c_cflag & tcflag_t(CSTOPB) != 0) != (line.stopBits == 2) { bad.append(L("\(String(line.stopBits)) bits de parada")) }
        if t.c_cflag & tcflag_t(CRTSCTS) != 0 || t.c_iflag & tcflag_t(IXON | IXOFF) != 0 { bad.append(L("sin control de flujo")) }
        return bad
    }

    static func size(_ bits: Int) -> tcflag_t {
        switch bits {
        case 5: tcflag_t(CS5)
        case 6: tcflag_t(CS6)
        case 7: tcflag_t(CS7)
        default: tcflag_t(CS8)
        }
    }

    static func why(_ code: Int32) -> String { String(cString: strerror(code)) }
}
