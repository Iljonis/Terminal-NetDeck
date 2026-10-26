import Darwin
import Foundation

/// Un proceso sin terminal (ssh con el subsistema sftp) con sus tres tuberías. Se lanza en una sesión propia (setsid):
/// sin terminal que lo controle, el askpass pregunta en una ventana y no en la terminal desde la que se abrió la app.
public final class ChildProcess: @unchecked Sendable {
    public let pid: pid_t
    /// Lo que escribe por su salida estándar, en orden; se acaba cuando la cierra.
    public let output: AsyncStream<Data>
    private let input: FileHandle
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let lock = NSLock()
    /// Si ya se ha recogido el proceso (y con qué estado): lo comparten la recogida y `terminate`, con su candado, aunque
    /// este objeto ya se esté liberando; así nunca se manda una señal a un PID recogido (y quizá ya de otro).
    private let reaped = Reaped()
    private var errorText = ""
    private var exitSource: DispatchSourceProcess?
    private let finishOutput: @Sendable () -> Void

    public init(executable: String, arguments: [String], environment: [String: String]) throws {
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inPipe.fileHandleForReading.fileDescriptor, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe.fileHandleForWriting.fileDescriptor, 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe.fileHandleForWriting.fileDescriptor, 2)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // (sesión propia; sólo hereda 0, 1 y 2; SIGPIPE como siempre aunque la app lo ignore; y las señales de parada
        // sin bloquear: lanzado desde un hilo de GCD, que las tiene bloqueadas, ni ssh ni su askpass recibían SIGTERM)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF
                                              | POSIX_SPAWN_SETSIGMASK))
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults)
        sigemptyset(&mask)
        for sig in [SIGPIPE, SIGTERM, SIGINT, SIGHUP] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &mask)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, executable, &actions, &attr, argv, envp)
        try? inPipe.fileHandleForReading.close()
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        guard rc == 0 else {
            throw RemoteError(L("No arranca \(executable): \(String(cString: strerror(rc)))"))
        }
        pid = child
        input = inPipe.fileHandleForWriting
        stdout = outPipe.fileHandleForReading
        stderr = errPipe.fileHandleForReading

        var cont: AsyncStream<Data>.Continuation!
        output = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        let c = cont!
        finishOutput = { c.finish() }
        stdout.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                c.finish()
            } else {
                c.yield(d)
            }
        }
        stderr.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.lock.withLock {
                self?.errorText += String(decoding: d, as: UTF8.self)
                if let s = self, s.errorText.count > 4000 { s.errorText = String(s.errorText.suffix(2000)) }
            }
        }
        let src = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .global())
        let reaped = reaped
        src.setEventHandler {
            // (WNOWAIT: el PID sigue reservado mientras se mata lo que quede de su grupo —el askpass que lanzó ssh, con
            // su ventana: sin terminal, nadie le manda SIGHUP— y luego se recoge; nunca una señal a un PID reciclado)
            var info = siginfo_t()
            var ready: Int32
            repeat { ready = waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) } while ready < 0 && errno == EINTR
            let reap: () -> Int32 = {
                if ready == 0 { killpg(child, SIGKILL) }
                var st: Int32 = 0, result: pid_t
                repeat { result = waitpid(child, &st, 0) } while result < 0 && errno == EINTR
                return st
            }
            reaped.lock.withLock { reaped.status = reap() }
            src.cancel()
        }
        exitSource = src
        src.resume()
    }

    deinit { terminate() }

    /// Lo último que ha dicho por su salida de errores (sin avisos «Warning: Permanently added…»).
    public var errorSummary: String {
        let lines = lock.withLock { errorText }.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Warning: Permanently added") && !$0.hasPrefix("**") }
        // (sin caracteres de control: el banner de un equipo no pinta ni mueve nada en la app ni en el registro)
        return String(lines.suffix(2).joined(separator: " · ").unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
    }

    public var exited: Bool { reaped.lock.withLock { reaped.status != nil } }

    public func write(_ d: Data) throws {
        do { try input.write(contentsOf: d) } catch { throw RemoteError(L("Se ha perdido la conexión")) }
    }

    public func terminate() {
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
        finishOutput()
        try? input.close()
        // (a todo su grupo: ssh y el askpass que haya lanzado. Sin recoger aún, el grupo es suyo: ver arriba)
        reaped.lock.withLock {
            guard reaped.status == nil else { return }
            if killpg(pid, SIGTERM) != 0 { kill(pid, SIGTERM) }
        }
    }
}

/// El estado de la recogida de un `ChildProcess`, con su candado (ver `ChildProcess.reaped`).
private final class Reaped: @unchecked Sendable {
    let lock = NSLock()
    var status: Int32?
}
