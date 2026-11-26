import Foundation
#if !os(Windows)
import Darwin
#else
import WinSDK
#endif

#if !os(Windows)
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
#else
// (macros de winbase.h / winerror.h que no llegan a Swift, con su valor)
private let kGenericReadWrite: DWORD = 0xC000_0000       // GENERIC_READ | GENERIC_WRITE
private let kOpenExisting: DWORD = 3
private let kFileFlagOverlapped: DWORD = 0x4000_0000
private let kErrorIOPending: DWORD = 997
private let kErrorWriteFault: DWORD = 29
private let kMaxDWORD: DWORD = 0xFFFF_FFFF
private let kPurgeAll: DWORD = 0x000F                    // PURGE_TXABORT | RXABORT | TXCLEAR | RXCLEAR
/// FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS
private let kFormatMessageFlags: DWORD = 0x0000_1000 | 0x0000_0200

/// Consola serie en Windows (COMn) sin programas externos: `CreateFileW` en exclusiva, `SetCommState` aplica la trama
/// y se relee para comprobarla. La E/S es solapada: un hilo lee y la cola `writer` escribe a la vez, sin que una
/// lectura pendiente retenga lo que se teclea. Misma interfaz que la de macOS.
public final class SerialPort: @unchecked Sendable {
    /// Por qué no se abre o no se configura (el texto, ya traducido, va a la pestaña y al aviso).
    public struct Failure: Error, LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
        public init(message: String) { self.message = message }
    }

    private let core: Core

    /// Abre `line.device`, aplica y comprueba la trama y empieza a leer. `onClose`: el puerto se ha cerrado solo
    /// (adaptador desenchufado, error de lectura o escritura), con el motivo; no se llama si lo cierra `close()`.
    public convenience init(_ line: SerialLine, queue: DispatchQueue,
                            onData: @escaping @Sendable (ArraySlice<UInt8>) -> Void,
                            onClose: @escaping @Sendable (String) -> Void) throws {
        try self.init(line, queue: queue, openDevice: { path in
            // (modo de compartición 0: nadie más abre el puerto mientras lo tenga la app)
            path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, kGenericReadWrite, 0, nil, kOpenExisting, kFileFlagOverlapped, nil)
            }
        }, onData: onData, onClose: onClose)
    }

    /// Apertura inyectable sólo para pruebas. El handle debe venir abierto con FILE_FLAG_OVERLAPPED.
    init(_ line: SerialLine, queue: DispatchQueue, openDevice: (String) -> HANDLE?,
         onData: @escaping @Sendable (ArraySlice<UInt8>) -> Void,
         onClose: @escaping @Sendable (String) -> Void) throws {
        if let p = line.problem { throw Failure(message: p) }
        let opened = openDevice(line.deviceForOpen)
        let openCode = GetLastError()
        guard let h = opened, h != INVALID_HANDLE_VALUE else {
            throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(openCode))"))
        }
        do { try Self.configure(handle: h, line: line) } catch { CloseHandle(h); throw error }
        // (eventos de reinicio manual, uno por sentido: los pide la E/S solapada)
        guard let readEvent = CreateEventW(nil, true, false, nil) else {
            let code = GetLastError()
            CloseHandle(h)
            throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(code))"))
        }
        guard let writeEvent = CreateEventW(nil, true, false, nil) else {
            let code = GetLastError()
            CloseHandle(readEvent); CloseHandle(h)
            throw Failure(message: L("No se puede abrir «\(line.device)»: \(Self.why(code))"))
        }
        PurgeComm(h, kPurgeAll)               // (lo que quedara en los búferes del controlador de antes de abrir)
        core = Core(handle: h, readEvent: readEvent, writeEvent: writeEvent, queue: queue, onClose: onClose)
        let core = core
        Thread.detachNewThread { core.readLoop(onData) }
    }

    deinit { _ = core.finish() }

    /// Lo que se teclea o se pega, tal cual.
    public func write(_ bytes: ArraySlice<UInt8>) { core.write(bytes) }

    /// BREAK nativo durante 250 ms (sin procesos externos ni una espera que retenga el cierre).
    public func sendBreak() { core.sendBreak() }

    public func close() { _ = core.finish() }

    /// El estado que comparten el puerto, el hilo lector y la cola de escritura. El hilo lo retiene hasta acabar: así
    /// el handle sigue siendo válido aunque `SerialPort` ya no exista, y sólo se cierra (en `writer`) cuando ni la
    /// lectura ni una escritura lo están usando.
    private final class Core: @unchecked Sendable {
        private let handle: HANDLE
        private let readEvent: HANDLE
        private let writeEvent: HANDLE
        private let writer = DispatchQueue(label: "netdeck.serie.escritura")
        private let queue: DispatchQueue
        private let onClose: @Sendable (String) -> Void
        private let lock = NSLock()
        private var closed = false
        private var breakGeneration = 0      // (sólo en writer)

        init(handle: HANDLE, readEvent: HANDLE, writeEvent: HANDLE, queue: DispatchQueue,
             onClose: @escaping @Sendable (String) -> Void) {
            self.handle = handle
            self.readEvent = readEvent
            self.writeEvent = writeEvent
            self.queue = queue
            self.onClose = onClose
        }

        private var isClosed: Bool { lock.withLock { closed } }

        /// El hilo lector. Cada lectura vuelve en cuanto hay algo o, sin datos, al segundo (`configure`): entonces se
        /// mira si se ha cerrado. Al salir libera el handle en `writer`, detrás de la escritura que estuviera en curso.
        func readLoop(_ onData: @escaping @Sendable (ArraySlice<UInt8>) -> Void) {
            let ov = UnsafeMutablePointer<OVERLAPPED>.allocate(capacity: 1)
            var buf = [UInt8](repeating: 0, count: 8192)
            while !isClosed {
                ov.initialize(to: OVERLAPPED())
                ov.pointee.hEvent = readEvent
                var n: DWORD = 0
                var ok = buf.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), nil, ov) }
                if ok || GetLastError() == kErrorIOPending { ok = GetOverlappedResult(handle, ov, &n, true) }
                let code = ok ? 0 : GetLastError()
                if isClosed { break }                     // (cancelada por close(): no es un fallo)
                if !ok { fail(SerialPort.why(code)); break }
                if n > 0 {
                    let chunk = buf[..<Int(n)]
                    queue.async { onData(chunk) }
                }
            }
            ov.deallocate()
            writer.async { [self] in
                ClearCommBreak(handle)
                PurgeComm(handle, kPurgeAll)   // (descartar también lo que el controlador aún no ha transmitido)
                CloseHandle(handle)
                CloseHandle(readEvent)
                CloseHandle(writeEvent)
            }
        }

        func write(_ bytes: ArraySlice<UInt8>) {
            guard !bytes.isEmpty, !isClosed else { return }
            let data = Array(bytes)
            writer.async { [self] in send(data) }
        }

        /// (en writer) Trozos de 4096: entre uno y otro se mira si se ha cerrado.
        private func send(_ data: [UInt8]) {
            var offset = 0
            while offset < data.count {
                guard !isClosed else { return }
                var n: DWORD = 0
                var ov = OVERLAPPED()
                ov.hEvent = writeEvent
                let code: DWORD = withUnsafeMutablePointer(to: &ov) { ov in
                    var ok = data[offset...].prefix(4096).withUnsafeBytes {
                        WriteFile(handle, $0.baseAddress, DWORD($0.count), nil, ov)
                    }
                    if ok || GetLastError() == kErrorIOPending { ok = GetOverlappedResult(handle, ov, &n, true) }
                    return ok ? 0 : GetLastError()
                }
                if code != 0 || n == 0 {
                    fail(L("No se puede escribir en el puerto: \(SerialPort.why(code == 0 ? kErrorWriteFault : code))"))
                    return
                }
                offset += Int(n)
            }
        }

        func sendBreak() {
            writer.async { [self] in
                guard !isClosed else { return }
                guard SetCommBreak(handle) else {
                    fail(L("No se puede enviar BREAK: \(SerialPort.why(GetLastError()))"))
                    return
                }
                breakGeneration += 1
                let generation = breakGeneration
                writer.asyncAfter(deadline: .now() + .milliseconds(250)) { [self] in
                    guard !isClosed, breakGeneration == generation else { return }
                    if !ClearCommBreak(handle) { fail(L("No se puede enviar BREAK: \(SerialPort.why(GetLastError()))")) }
                }
            }
        }

        private func fail(_ reason: String) {
            if finish() { let onClose = onClose; queue.async { onClose(reason) } }
        }

        /// true la primera vez. `CancelIoEx` va con el candado: el hilo lector no puede ver `closed` (y soltar el
        /// handle) antes de que la cancelación haya terminado.
        func finish() -> Bool {
            lock.withLock {
                if closed { return false }
                closed = true
                CancelIoEx(handle, nil)       // (despierta la lectura y corta la escritura en curso)
                return true
            }
        }
    }

    // MARK: - DCB

    /// Aplica la trama de `line` (binario, sin control de flujo, DTR y RTS activos) y la relee: si el controlador no
    /// ha cogido algún valor, error con lo que falta. Deja las lecturas con un segundo de espera como mucho.
    static func configure(handle h: HANDLE, line: SerialLine) throws {
        if let p = line.problem { throw Failure(message: p) }
        var dcb = DCB()
        dcb.DCBlength = DWORD(MemoryLayout<DCB>.size)
        guard GetCommState(h, &dcb) else {
            throw Failure(message: L("El puerto no admite configuración: \(why(GetLastError()))"))
        }
        dcb.BaudRate = DWORD(line.speed)
        dcb.ByteSize = BYTE(line.dataBits)
        dcb.Parity = parity(line.parity)
        dcb.StopBits = stopBits(line.stopBits)
        dcb.fBinary = 1
        dcb.fParity = line.parity == .none ? 0 : 1
        dcb.fOutxCtsFlow = 0
        dcb.fOutxDsrFlow = 0
        dcb.fDtrControl = 1                   // DTR_CONTROL_ENABLE
        dcb.fDsrSensitivity = 0
        dcb.fOutX = 0
        dcb.fInX = 0
        dcb.fErrorChar = 0
        dcb.fNull = 0
        dcb.fRtsControl = 1                   // RTS_CONTROL_ENABLE
        dcb.fAbortOnError = 0                 // (un error de trama no deja la E/S parada hasta ClearCommError)
        guard SetCommState(h, &dcb) else {
            throw Failure(message: L("El puerto no acepta \(String(line.speed)) \(line.frame): \(why(GetLastError()))"))
        }
        var got = DCB()
        got.DCBlength = DWORD(MemoryLayout<DCB>.size)
        guard GetCommState(h, &got) else {
            throw Failure(message: L("El puerto no admite configuración: \(why(GetLastError()))"))
        }
        let bad = mismatches(line, got)
        if !bad.isEmpty { throw Failure(message: L("El puerto no ha aceptado: \(bad.joined(separator: ", "))")) }
        // MAXDWORD, MAXDWORD, 1000: la lectura vuelve en cuanto llega algo y, sin datos, al segundo. Sin límite al
        // escribir (no hay control de flujo que la retenga; `close()` la cancela).
        var timeouts = COMMTIMEOUTS(ReadIntervalTimeout: kMaxDWORD, ReadTotalTimeoutMultiplier: kMaxDWORD,
                                    ReadTotalTimeoutConstant: 1000, WriteTotalTimeoutMultiplier: 0,
                                    WriteTotalTimeoutConstant: 0)
        guard SetCommTimeouts(h, &timeouts) else {
            throw Failure(message: L("El puerto no admite configuración: \(why(GetLastError()))"))
        }
    }

    /// Lo que de `line` no está en `dcb` (vacío: todo aplicado).
    static func mismatches(_ line: SerialLine, _ dcb: DCB) -> [String] {
        var bad: [String] = []
        if Int(dcb.BaudRate) != line.speed {
            bad.append(L("velocidad \(String(line.speed)) (queda \(String(Int(dcb.BaudRate))))"))
        }
        if Int(dcb.ByteSize) != line.dataBits { bad.append(L("\(String(line.dataBits)) bits de datos")) }
        if dcb.Parity != parity(line.parity) { bad.append(L("paridad \(line.parity.rawValue)")) }
        if dcb.StopBits != stopBits(line.stopBits) { bad.append(L("\(String(line.stopBits)) bits de parada")) }
        if dcb.fOutxCtsFlow != 0 || dcb.fOutX != 0 || dcb.fInX != 0 { bad.append(L("sin control de flujo")) }
        return bad
    }

    /// NOPARITY 0, ODDPARITY 1, EVENPARITY 2.
    static func parity(_ p: SerialLine.Parity) -> BYTE {
        switch p {
        case .none: 0
        case .odd: 1
        case .even: 2
        }
    }

    /// ONESTOPBIT 0, TWOSTOPBITS 2.
    static func stopBits(_ n: Int) -> BYTE { n == 2 ? 2 : 0 }

    /// El mensaje de Windows para el código (en el idioma del sistema) y el código.
    static func why(_ code: DWORD) -> String {
        var buffer = [WCHAR](repeating: 0, count: 512)
        let n = FormatMessageW(kFormatMessageFlags, nil, code, 0, &buffer, DWORD(buffer.count), nil)
        let text = String(decoding: buffer.prefix(Int(n)), as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "error \(code)" : "\(text) (\(code))"
    }
}
#endif
