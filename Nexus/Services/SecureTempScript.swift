import Foundation

/// Creates short-lived helper scripts (SSH_ASKPASS) with owner-only permissions from
/// the instant of creation, and cleans up ones a crash may have left behind.
///
/// Why not `String.write(atomically:) + chmod`: the atomic write creates the file with
/// the process umask (typically world-readable 0644) and only narrows it afterwards,
/// leaving a brief window where the password script is readable by other processes.
/// Creating with `open(O_CREAT | O_EXCL | O_WRONLY, 0o700)` closes that window (the file
/// is owner-only immediately) and `O_EXCL` defeats a symlink planted at the path.
enum SecureTempScript {

    /// Writes `contents` to a new `0700` file `<prefix>_<uuid>.sh` in the per-user temp
    /// directory. Returns the path, or nil on failure.
    static func write(_ contents: String, prefix: String) -> String? {
        let path = NSTemporaryDirectory() + "\(prefix)_\(UUID().uuidString).sh"
        let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o700)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let bytes = Array(contents.utf8)
        var written = 0
        bytes.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            while written < buf.count {
                let n = Foundation.write(fd, base.advanced(by: written), buf.count - written)
                if n <= 0 { break }
                written += n
            }
        }
        guard written == bytes.count else { unlink(path); return nil }
        return path
    }
}
