#if os(Windows)
import WinSDK
#else
import Darwin
#endif
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
    #if os(Windows)
    /// El proceso y su Job Object (ver `WindowsChild`).
    private let windowsChild: WindowsChild
    #else
    private var exitSource: DispatchSourceProcess?
    #endif
    private let finishOutput: @Sendable () -> Void

    public init(executable: String, arguments: [String], environment: [String: String]) throws {
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()

        #if os(Windows)
        // (CreateProcessW y no Foundation.Process: sin ventana de consola, sólo hereda las tres tuberías y va en un
        // Job Object que se lleva por delante a ssh y a lo que haya lanzado; ver `WindowsChild`)
        let spawn = Result {
            try WindowsChild(executable: executable, arguments: arguments, environment: environment,
                             stdin: inPipe.fileHandleForReading, stdout: outPipe.fileHandleForWriting,
                             stderr: errPipe.fileHandleForWriting)
        }
        try? inPipe.fileHandleForReading.close()
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        let spawned: WindowsChild
        switch spawn {
        case .success(let s): spawned = s
        case .failure(let e):
            throw RemoteError(L("No arranca \(executable): \((e as? WindowsSpawnError)?.detail ?? "")"))
        }
        windowsChild = spawned
        let child: pid_t = spawned.pid
        #else
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
        #endif

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

        #if os(Windows)
        // (DispatchSourceProcess no existe en Windows: un hilo espera el fin con WaitForSingleObject)
        spawned.watch(reaped)
        #else
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
        #endif
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
            #if os(Windows)
            windowsChild.terminateTree()
            #else
            if killpg(pid, SIGTERM) != 0 { kill(pid, SIGTERM) }
            #endif
        }
    }
}

/// El estado de la recogida de un `ChildProcess`, con su candado (ver `ChildProcess.reaped`).
private final class Reaped: @unchecked Sendable {
    let lock = NSLock()
    var status: Int32?
}

#if os(Windows)
// MARK: - Windows

// (macros de <winbase.h> y <winnt.h> que WinSDK no lleva a Swift, o que lleva con otro tipo)
private let kCreateSuspended: DWORD = 0x0000_0004
private let kCreateNewProcessGroup: DWORD = 0x0000_0200
private let kCreateUnicodeEnvironment: DWORD = 0x0000_0400
private let kExtendedStartupInfoPresent: DWORD = 0x0008_0000
private let kCreateNoWindow: DWORD = 0x0800_0000
private let kStartfUseStdHandles: DWORD = 0x0000_0100
private let kDuplicateSameAccess: DWORD = 0x0000_0002
/// PROC_THREAD_ATTRIBUTE_HANDLE_LIST = ProcThreadAttributeValue(2, FALSE, TRUE, FALSE)
private let kAttributeHandleList: DWORD_PTR = 0x0002_0002
private let kJobLimitKillOnJobClose: DWORD = 0x0000_2000
private let kInfinite: DWORD = 0xFFFF_FFFF
private let kWaitObject0: DWORD = 0
private let kResumeFailed: DWORD = 0xFFFF_FFFF
/// FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS
private let kFormatMessageFlags: DWORD = 0x0000_1000 | 0x0000_0200
private let kErrorNotSupported: DWORD = 50
private let kErrorInvalidParameter: DWORD = 87

/// Por qué no ha arrancado: el mensaje de Windows para el código de error (en el idioma del sistema) y, entre
/// paréntesis, la llamada y el código. Nunca lleva argumentos ni entorno del proceso.
private struct WindowsSpawnError: Error {
    let detail: String

    init(_ call: String, code: DWORD = GetLastError()) {
        var buffer = [WCHAR](repeating: 0, count: 512)
        let n = FormatMessageW(kFormatMessageFlags, nil, code, 0, &buffer, DWORD(buffer.count), nil)
        let text = String(decoding: buffer.prefix(Int(n)), as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        detail = text.isEmpty ? "\(call) \(code)" : "\(text) (\(call) \(code))"
    }
}

/// Un proceso de Windows lanzado con `CreateProcessW`, sin ventana de consola (`CREATE_NO_WINDOW`), en su propio grupo
/// (`CREATE_NEW_PROCESS_GROUP`) y dentro de un Job Object propio con `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`: lo que en
/// macOS hacen `setsid` y `killpg`. Al terminar el Job (o al cerrarse su handle, también si la app muere sin avisar)
/// se van ssh y todo lo que haya lanzado (el askpass, un ProxyCommand). Sólo hereda las tres tuberías
/// (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`).
private final class WindowsChild: @unchecked Sendable {
    let pid: pid_t
    // (los cierra `watch` al recoger el proceso, con el candado de `Reaped`: mientras `status` sea nil, valen)
    private let process: HANDLE
    private let job: HANDLE

    init(executable: String, arguments: [String], environment: [String: String],
         stdin: FileHandle, stdout: FileHandle, stderr: FileHandle) throws {
        // (un .bat o .cmd lo ejecutaría cmd.exe con sus propias reglas de comillas, y un argumento podría colar una
        // orden; un NUL cortaría la línea de órdenes)
        let name = executable.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard !name.hasSuffix(".bat"), !name.hasSuffix(".cmd") else {
            throw WindowsSpawnError("bat/cmd", code: kErrorNotSupported)
        }
        guard !([executable] + arguments).contains(where: { $0.unicodeScalars.contains("\0") }) else {
            throw WindowsSpawnError("argv", code: kErrorInvalidParameter)
        }

        // Copias heredables de las tres tuberías (las de Foundation no lo son): sólo ésas pasan al hijo.
        let me = GetCurrentProcess()
        var inherited: [HANDLE] = []
        defer { inherited.forEach { CloseHandle($0) } }
        for source in [stdin, stdout, stderr] {
            var copy: HANDLE?
            guard DuplicateHandle(me, source._handle, me, &copy, 0, true, kDuplicateSameAccess), let copy else {
                throw WindowsSpawnError("DuplicateHandle")
            }
            inherited.append(copy)
        }

        guard let hJob = CreateJobObjectW(nil, nil) else { throw WindowsSpawnError("CreateJobObjectW") }
        var launched = false
        defer { if !launched { CloseHandle(hJob) } }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = kJobLimitKillOnJobClose
        guard SetInformationJobObject(hJob, JobObjectExtendedLimitInformation, &limits,
                                      DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)) else {
            throw WindowsSpawnError("SetInformationJobObject")
        }

        var size: SIZE_T = 0
        InitializeProcThreadAttributeList(nil, 1, 0, &size)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), 1),
                                                      alignment: MemoryLayout<UInt>.alignment)
        defer { memory.deallocate() }
        let attributes: LPPROC_THREAD_ATTRIBUTE_LIST = OpaquePointer(memory)
        guard InitializeProcThreadAttributeList(attributes, 1, 0, &size) else {
            throw WindowsSpawnError("InitializeProcThreadAttributeList")
        }
        defer { DeleteProcThreadAttributeList(attributes) }
        // (la lista tiene que seguir en su sitio hasta DeleteProcThreadAttributeList)
        let list = UnsafeMutablePointer<HANDLE?>.allocate(capacity: inherited.count)
        defer { list.deallocate() }
        for (i, h) in inherited.enumerated() { list[i] = h }
        guard UpdateProcThreadAttribute(attributes, 0, kAttributeHandleList, list,
                                        SIZE_T(inherited.count * MemoryLayout<HANDLE?>.size), nil, nil) else {
            throw WindowsSpawnError("UpdateProcThreadAttribute")
        }

        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.StartupInfo.dwFlags = kStartfUseStdHandles
        startup.StartupInfo.hStdInput = inherited[0]
        startup.StartupInfo.hStdOutput = inherited[1]
        startup.StartupInfo.hStdError = inherited[2]
        startup.lpAttributeList = attributes

        // (el ejecutable va aparte, con su ruta: no se busca en el PATH, como con posix_spawn)
        var application = Array(executable.utf16) + [0]
        var command = Array(Self.commandLine(executable, arguments).utf16) + [0]
        var block = windowsEnvironmentBlock(environment)
        // (parado hasta estar en el Job: ningún nieto se queda fuera)
        let flags = kCreateSuspended | kCreateNoWindow | kCreateNewProcessGroup | kCreateUnicodeEnvironment
            | kExtendedStartupInfoPresent
        var info = PROCESS_INFORMATION()
        let created = withUnsafeMutablePointer(to: &startup) {
            $0.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { si in
                CreateProcessW(&application, &command, nil, nil, true, flags, &block, nil, si, &info)
            }
        }
        guard created, let hProcess = info.hProcess, let hThread = info.hThread else {
            throw WindowsSpawnError("CreateProcessW")
        }
        defer { CloseHandle(hThread) }
        guard AssignProcessToJobObject(hJob, hProcess) else {
            let error = WindowsSpawnError("AssignProcessToJobObject")
            TerminateProcess(hProcess, 1)
            CloseHandle(hProcess)
            throw error
        }
        guard ResumeThread(hThread) != kResumeFailed else {
            let error = WindowsSpawnError("ResumeThread")
            TerminateProcess(hProcess, 1)
            CloseHandle(hProcess)
            throw error
        }
        launched = true
        pid = pid_t(truncatingIfNeeded: info.dwProcessId)
        process = hProcess
        job = hJob
    }

    /// Espera el fin en un hilo y lo apunta en `reaped`. Antes mata lo que quede en el Job (el askpass que lanzó ssh,
    /// con su ventana) y cierra los handles, todo con el candado: `terminateTree` nunca toca un handle cerrado.
    func watch(_ reaped: Reaped) {
        Thread.detachNewThread { [self] in
            var code: DWORD = 0
            var known = WaitForSingleObject(process, kInfinite) == kWaitObject0
            if known { known = GetExitCodeProcess(process, &code) }
            reaped.lock.withLock {
                TerminateJobObject(job, 1)
                reaped.status = known ? Int32(bitPattern: code) : -1
                CloseHandle(process)
                CloseHandle(job)
            }
        }
    }

    /// A todo el Job: ssh y lo que haya lanzado. Sólo con el candado de `Reaped` y sin recoger aún (ver `watch`).
    /// (sin consola compartida no hay Ctrl+Break que mandarle: la parada amable es cerrarle la entrada, ya hecho)
    func terminateTree() {
        TerminateJobObject(job, 1)
    }

    /// La línea de órdenes, con las comillas que deshacen `CommandLineToArgvW` y el runtime de C.
    static func commandLine(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map(quoted).joined(separator: " ")
    }

    // (por escalares Unicode y no por caracteres: una comilla seguida de un acento combinable es otro «carácter» para
    // Swift, pero para Windows sigue siendo una comilla)
    private static func quoted(_ argument: String) -> String {
        let quote: Unicode.Scalar = "\"", slash: Unicode.Scalar = "\\"
        let scalars = argument.unicodeScalars
        guard scalars.isEmpty || scalars.contains(where: { $0 == " " || $0 == "\t" || $0 == quote }) else {
            return argument
        }
        var out = String.UnicodeScalarView()
        out.append(quote)
        var slashes = 0
        for s in scalars {
            if s == slash { slashes += 1; continue }
            // (las barras de delante de una comilla se doblan, y la comilla lleva la suya; las demás van tal cual)
            out.append(contentsOf: repeatElement(slash, count: s == quote ? slashes * 2 + 1 : slashes))
            out.append(s)
            slashes = 0
        }
        out.append(contentsOf: repeatElement(slash, count: slashes * 2))
        out.append(quote)
        return String(out)
    }
}

/// El entorno como lo quiere `CREATE_UNICODE_ENVIRONMENT`: «nombre=valor» en UTF-16 acabados en NUL, ordenados por
/// nombre y con otro NUL al final. Lo que no cabe en ese formato (sin nombre, «=» en el nombre o un NUL) no pasa.
func windowsEnvironmentBlock(_ environment: [String: String]) -> [WCHAR] {
    let valid = environment.filter { key, value in
        !key.isEmpty && !key.unicodeScalars.contains("=") && !key.unicodeScalars.contains("\0")
            && !value.unicodeScalars.contains("\0")
    }
    var block: [WCHAR] = []
    for (key, value) in valid.sorted(by: { $0.key.uppercased() < $1.key.uppercased() }) {
        block.append(contentsOf: "\(key)=\(value)".utf16)
        block.append(0)
    }
    if block.isEmpty { block.append(0) }
    block.append(0)
    return block
}
#endif
