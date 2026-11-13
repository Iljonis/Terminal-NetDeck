#if os(Windows)
import WinSDK
import Foundation

// PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE no se exporta como macro desde WinSDK Swift.
// ProcThreadAttributeValue(22, FALSE, TRUE, FALSE) = 0x00020016
private let kConPTYAttr: DWORD_PTR = 0x00020016
private let kExtStartup: DWORD = 0x00080000
private let kUnicodeEnv: DWORD   = 0x00000400
private let kNoWindow: DWORD     = 0x08000000

/// Proceso con pseudo-terminal (ConPTY) para Windows.
/// Equivalente a LocalProcess/forkpty de SwiftTerm en macOS.
public final class ConPTYProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var hPC: HPCON?
    private var hProcess: HANDLE = INVALID_HANDLE_VALUE
    private let ptyInWrite: HANDLE
    private var done = false

    public let output: AsyncStream<Data>
    private let _finish: @Sendable () -> Void

    public init(executable: String, arguments: [String], environment: [String: String],
                cols: Int = 80, rows: Int = 24) throws {
        var ptyInR:  HANDLE? = nil
        var ptyInW:  HANDLE? = nil
        var ptyOutR: HANDLE? = nil
        var ptyOutW: HANDLE? = nil

        guard CreatePipe(&ptyInR, &ptyInW, nil, 0),
              let ptyInR, let ptyInW else {
            throw RemoteError(L("No arranca \(executable): tuberias de entrada"))
        }
        guard CreatePipe(&ptyOutR, &ptyOutW, nil, 0),
              let ptyOutR, let ptyOutW else {
            CloseHandle(ptyInR); CloseHandle(ptyInW)
            throw RemoteError(L("No arranca \(executable): tuberias de salida"))
        }

        let coord = COORD(X: Int16(min(max(cols, 1), 32767)), Y: Int16(min(max(rows, 1), 32767)))
        var hpc: HPCON?
        let hr = CreatePseudoConsole(coord, ptyInR, ptyOutW, 0, &hpc)
        CloseHandle(ptyInR)
        CloseHandle(ptyOutW)
        guard hr == S_OK, let hpcVal = hpc else {
            CloseHandle(ptyInW); CloseHandle(ptyOutR)
            throw RemoteError(L("No arranca \(executable): CreatePseudoConsole 0x\(String(UInt32(bitPattern: hr), radix: 16))"))
        }
        hPC = hpcVal
        ptyInWrite = ptyInW

        var cont: AsyncStream<Data>.Continuation!
        output = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        let c = cont!
        _finish = { c.finish() }

        // Convertir HANDLE (UnsafeMutableRawPointer, no Sendable) a Int para cruzar el limite @Sendable.
        let ptyOutRAddr = Int(bitPattern: ptyOutR)
        Thread.detachNewThread {
            let ptyOutR: HANDLE = UnsafeMutableRawPointer(bitPattern: ptyOutRAddr)!
            defer { CloseHandle(ptyOutR) }
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                var n: DWORD = 0
                let ok = buf.withUnsafeMutableBytes { ReadFile(ptyOutR, $0.baseAddress!, DWORD($0.count), &n, nil) }
                guard ok, n > 0 else { break }
                c.yield(Data(buf[..<Int(n)]))
            }
            c.finish()
        }

        var attrSize: SIZE_T = 0
        InitializeProcThreadAttributeList(nil, 1, 0, &attrSize)
        let attrMem = UnsafeMutableRawBufferPointer.allocate(byteCount: Int(attrSize),
                                                              alignment: MemoryLayout<UInt>.alignment)
        defer { attrMem.deallocate() }
        guard let attrBase = attrMem.baseAddress else {
            throw RemoteError(L("No arranca \(executable): atributos (alloc)"))
        }
        let attrList: LPPROC_THREAD_ATTRIBUTE_LIST = OpaquePointer(attrBase)
        guard InitializeProcThreadAttributeList(attrList, 1, 0, &attrSize) else {
            throw RemoteError(L("No arranca \(executable): InitializeProcThreadAttributeList"))
        }
        defer { DeleteProcThreadAttributeList(attrList) }

        var hpcForAttr: HPCON? = hpcVal
        guard withUnsafeMutablePointer(to: &hpcForAttr, { p in
            UpdateProcThreadAttribute(attrList, 0, kConPTYAttr,
                                      UnsafeMutableRawPointer(p), SIZE_T(MemoryLayout<HPCON?>.size),
                                      nil, nil)
        }) else {
            throw RemoteError(L("No arranca \(executable): UpdateProcThreadAttribute"))
        }

        var siEx = STARTUPINFOEXW()
        siEx.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        siEx.lpAttributeList = attrList

        var pi = PROCESS_INFORMATION()
        let cmd = ConPTYProcess.commandLine(executable, arguments)
        let envB = ConPTYProcess.envBlock(environment)
        let flags = kExtStartup | kUnicodeEnv | kNoWindow

        let launched: Bool = cmd.withUTF16CStr { cmdW in
            envB.withUnsafeBytes { envBuf in
                withUnsafeMutablePointer(to: &siEx) { siExPtr in
                    siExPtr.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { siPtr in
                        CreateProcessW(nil, cmdW, nil, nil, false, flags,
                                       UnsafeMutableRawPointer(mutating: envBuf.baseAddress!),
                                       nil, siPtr, &pi)
                    }
                }
            }
        }
        guard launched else {
            throw RemoteError(L("No arranca \(executable)"))
        }
        hProcess = pi.hProcess ?? INVALID_HANDLE_VALUE
        if let ht = pi.hThread { CloseHandle(ht) }
    }

    deinit { terminate() }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { ptr in
            var written: DWORD = 0
            guard WriteFile(ptyInWrite, ptr.baseAddress!, DWORD(ptr.count), &written, nil) else {
                throw RemoteError(L("Se ha perdido la conexion"))
            }
        }
    }

    public func resize(cols: Int, rows: Int) {
        let hpc = lock.withLock { hPC }
        guard let hpc else { return }
        ResizePseudoConsole(hpc, COORD(X: Int16(min(max(cols, 1), 32767)), Y: Int16(min(max(rows, 1), 32767))))
    }

    public func terminate() {
        lock.withLock {
            guard !done else { return }
            done = true
            _finish()
            CloseHandle(ptyInWrite)
            if hProcess != INVALID_HANDLE_VALUE {
                TerminateProcess(hProcess, 1)
                CloseHandle(hProcess)
                hProcess = INVALID_HANDLE_VALUE
            }
            if let hpc = hPC { ClosePseudoConsole(hpc); hPC = nil }
        }
    }

    // MARK: - Helpers privados

    private static func commandLine(_ exe: String, _ args: [String]) -> String {
        let dq = Character(UnicodeScalar(34)!)
        let bsl = Character(UnicodeScalar(92)!)
        return ([exe] + args).map { arg in
            guard arg.contains(dq) || arg.contains(bsl) || arg.contains(" ") || arg.isEmpty else { return arg }
            var r = String(dq)
            for c in arg {
                if c == bsl { r.append(bsl); r.append(bsl) }
                else if c == dq { r.append(bsl); r.append(dq) }
                else { r.append(c) }
            }
            r.append(dq)
            return r
        }.joined(separator: " ")
    }

    private static func envBlock(_ env: [String: String]) -> [UInt16] {
        var block: [UInt16] = []
        for (k, v) in env { ("\(k)=\(v)\0").utf16.forEach { block.append($0) } }
        block.append(0)
        return block
    }
}

private extension String {
    func withUTF16CStr<T>(_ body: (UnsafeMutablePointer<WCHAR>?) throws -> T) rethrows -> T {
        var chars = Array(self.utf16) + [UInt16(0)]
        return try chars.withUnsafeMutableBufferPointer { buf in
            try buf.baseAddress!.withMemoryRebound(to: WCHAR.self, capacity: buf.count, body)
        }
    }
}
#endif