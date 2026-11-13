#if os(Windows)
import Foundation

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

// Process liveness check — used by CredentialLedger.
// The current process is always alive; others stub as dead (TODO P4d: OpenProcess/GetExitCodeProcess from WinSDK).
public func _windowsProcessAlive(_ pid: Int32) -> Bool {
    if pid == ProcessInfo.processInfo.processIdentifier { return true }
    return false
}

// lstat: POSIX stat without symlink following (Windows has no equivalent; uses regular stat)
@discardableResult
public func lstat(_ path: String, _ buf: UnsafeMutablePointer<stat>) -> Int32 { stat(path, buf) }

// flock: POSIX advisory file locking (not on Windows) — no-op stubs (TODO P4f: use LockFile/UnlockFile).
public let LOCK_EX: Int32 = 2
public let LOCK_UN: Int32 = 8
@discardableResult
public func flock(_ fd: Int32, _ operation: Int32) -> Int32 { 0 }

// kill: señal POSIX (no existe en Windows). Señal 0 comprueba si el proceso sigue vivo.
// Las demás se ignoran (TODO P4f: usar TerminateProcess/OpenProcess de WinSDK).
@discardableResult
public func kill(_ pid: pid_t, _ sig: Int32) -> Int32 {
    if sig == 0 { return _windowsProcessAlive(pid) ? 0 : -1 }
    return 0 // no-op: señales de terminación no implementadas
}
#endif