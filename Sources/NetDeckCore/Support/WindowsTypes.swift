#if os(Windows)
import Foundation
import WinSDK

// POSIX types and constants not available on Windows — defined here for API compatibility.
public typealias pid_t = Int32
public let SIGKILL: Int32 = 9
// O_CLOEXEC and O_NOFOLLOW are POSIX extensions not in Windows UCRT; stub as 0 (TODO P4f).
public let O_CLOEXEC: Int32 = 0
public let O_NOFOLLOW: Int32 = 0

// localtime_r: POSIX reentrant localtime (not on Windows); implemented via localtime.
@discardableResult
public func localtime_r(_ timer: UnsafePointer<time_t>?, _ result: UnsafeMutablePointer<tm>?) -> UnsafeMutablePointer<tm>? {
    guard let timer, let result, let p = localtime(timer) else { return nil }
    result.pointee = p.pointee
    return result
}

// fnmatch: POSIX pattern matching (not on Windows) — simple * and ? shell glob matching.
// Returns 0 on match (matches POSIX convention).
public func fnmatch(_ pattern: String, _ string: String, _ flags: Int32) -> Int32 {
    _fnmatch(pattern[pattern.startIndex...], string[string.startIndex...]) ? 0 : 1
}
private func _fnmatch(_ p: Substring, _ s: Substring) -> Bool {
    var pi = p.startIndex, si = s.startIndex
    while pi < p.endIndex && si < s.endIndex {
        let pc = p[pi]
        if pc == "*" {
            let next = p.index(after: pi)
            if next == p.endIndex { return true }
            var ti = si
            while ti <= s.endIndex {
                if _fnmatch(p[next...], s[ti...]) { return true }
                if ti == s.endIndex { break }
                ti = s.index(after: ti)
            }
            return false
        } else if pc == "?" {
            pi = p.index(after: pi)
            si = s.index(after: si)
        } else if pc == s[si] {
            pi = p.index(after: pi)
            si = s.index(after: si)
        } else {
            return false
        }
    }
    while pi < p.endIndex && p[pi] == "*" { pi = p.index(after: pi) }
    return pi == p.endIndex && si == s.endIndex
}

// Process liveness check (P4a) — used by CredentialLedger (P4d) and Askpass (P4e).
// macOS asks with kill(pid, 0); Windows has no signals: OpenProcess + GetExitCodeProcess.
public enum ProcessAlive {
    private static let queryLimitedInformation: DWORD = 0x1000   // PROCESS_QUERY_LIMITED_INFORMATION
    private static let stillActive: DWORD = 259                  // STILL_ACTIVE
    private static let accessDenied: DWORD = 5                   // ERROR_ACCESS_DENIED

    /// Is `pid` still running? A process we are not allowed to open counts as alive (it exists), like EPERM on macOS.
    public static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let id = DWORD(pid)
        if id == GetCurrentProcessId() { return true }
        guard let handle = OpenProcess(queryLimitedInformation, false, id) else {
            return GetLastError() == accessDenied
        }
        defer { CloseHandle(handle) }
        var code: DWORD = 0
        guard GetExitCodeProcess(handle, &code) else { return false }
        return code == stillActive
    }
}

// Kept for the callers written before `ProcessAlive` existed (CredentialLedger, `kill(pid, 0)` below).
public func _windowsProcessAlive(_ pid: Int32) -> Bool { ProcessAlive.isAlive(pid) }

// lstat: POSIX stat without symlink following (Windows has no equivalent; uses regular stat)
@discardableResult
public func lstat(_ path: String, _ buf: UnsafeMutablePointer<stat>) -> Int32 { stat(path, buf) }

// Candado entre procesos (P4d): lo que en macOS hace open + flock(LOCK_EX) sobre un archivo. Windows no tiene flock y
// LockFileEx pide un HANDLE, no un descriptor POSIX: se abre el archivo con CreateFileW y se bloquea su primer byte.
// El candado es del HANDLE: otro proceso (el askpass) u otro HANDLE de este mismo proceso esperan hasta que se suelte,
// y si el proceso muere Windows lo suelta al cerrar el HANDLE, igual que flock.
public enum FileLock {
    private static let genericReadWrite: DWORD = 0xC000_0000     // GENERIC_READ | GENERIC_WRITE
    private static let shareAll: DWORD = 0x7                     // FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
    private static let openAlways: DWORD = 4                     // OPEN_ALWAYS
    private static let attributeNormal: DWORD = 0x80             // FILE_ATTRIBUTE_NORMAL
    private static let exclusiveLock: DWORD = 0x2                // LOCKFILE_EXCLUSIVE_LOCK

    /// Abre (o crea) `path` y espera hasta tener el candado exclusivo. `nil` si no se puede abrir o bloquear.
    public static func acquire(_ path: String) -> HANDLE? {
        let handle = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, genericReadWrite, shareAll, nil, openAlways, attributeNormal, nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        var overlapped = OVERLAPPED()
        guard LockFileEx(handle, exclusiveLock, 0, 1, 0, &overlapped) else {
            CloseHandle(handle)
            return nil
        }
        return handle
    }

    /// Suelta el candado y cierra el HANDLE.
    public static func release(_ handle: HANDLE) {
        var overlapped = OVERLAPPED()
        UnlockFileEx(handle, 0, 1, 0, &overlapped)
        CloseHandle(handle)
    }
}

// abre un archivo nuevo sin seguir reparse points (el O_EXCL+O_NOFOLLOW seguro en Windows).
// Fija errno=EEXIST si el archivo ya existe, EIO en otro caso; devuelve el descriptor o -1.
public func _windowsOpenExclNoFollow(_ path: String, shareRead: Bool = false) -> Int32 {
    let genericWrite: DWORD = 0x4000_0000   // GENERIC_WRITE
    let sharing: DWORD = shareRead ? 1 : 0   // FILE_SHARE_READ (lectores del registro en vivo)
    let createNew: DWORD = 1                // CREATE_NEW: falla si ya existe (O_EXCL)
    let attrAndFlags: DWORD = 0x0020_0080   // FILE_FLAG_OPEN_REPARSE_POINT | FILE_ATTRIBUTE_NORMAL
    let handle = path.withCString(encodedAs: UTF16.self) {
        CreateFileW($0, genericWrite, sharing, nil, createNew, attrAndFlags, nil)
    }
    guard let handle, handle != INVALID_HANDLE_VALUE else {
        // Mapeamos el error de Windows a errno para que el caller (open-style loop) funcione igual.
        _errno().pointee = GetLastError() == 183 ? EEXIST : EIO   // 183 = ERROR_FILE_EXISTS
        return -1
    }
    let fd = _open_osfhandle(Int(bitPattern: handle), 0x0001)  // _O_WRONLY
    if fd < 0 { CloseHandle(handle); _errno().pointee = EIO }
    return fd
}

// kill: señal POSIX (no existe en Windows). Señal 0 comprueba si el proceso sigue vivo.
// Las demás se ignoran (TODO P4f: usar TerminateProcess/OpenProcess de WinSDK).
@discardableResult
public func kill(_ pid: pid_t, _ sig: Int32) -> Int32 {
    if sig == 0 { return _windowsProcessAlive(pid) ? 0 : -1 }
    return 0 // no-op: señales de terminación no implementadas
}

/// PID del proceso padre del proceso actual.
/// Implementa la semantica de getppid() usando CreateToolhelp32Snapshot + Process32FirstW/NextW.
/// Devuelve 0 si no se puede obtener (el proceso desaparecio antes de leerlo).
func _windowsGetppid() -> pid_t {
    let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
    guard snapshot != INVALID_HANDLE_VALUE else { return 0 }
    defer { CloseHandle(snapshot) }
    var entry = PROCESSENTRY32W()
    entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
    let selfPID = DWORD(ProcessInfo.processInfo.processIdentifier)
    guard Process32FirstW(snapshot, &entry) else { return 0 }
    repeat {
        if entry.th32ProcessID == selfPID {
            return pid_t(entry.th32ParentProcessID)
        }
    } while Process32NextW(snapshot, &entry)
    return 0
}
#endif
