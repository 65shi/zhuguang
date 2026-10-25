import Foundation
import Darwin

/// A process-lifetime lock shared by GUI and rendering diagnostics. Keeping the
/// same inode (rather than unlinking on exit) avoids a second process locking a
/// newly created file while an older instance still owns the previous one.
final class InstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Returns nil only when another process holds the lock. All filesystem and
    /// permission failures are thrown so callers can fail closed before drawing.
    static func acquire() throws -> InstanceLock? {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true)
        let directory = support.appendingPathComponent("SmartLight", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("instance.lock", isDirectory: false)
        let fd = Darwin.open(file.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw ioError(errno, path: file.path) }

        var ownsDescriptor = true
        defer { if ownsDescriptor { Darwin.close(fd) } }

        var info = stat()
        guard Darwin.fstat(fd, &info) == 0 else { throw ioError(errno, path: file.path) }
        // Refuse devices, directories, and hard links before changing permissions.
        guard info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1 else {
            throw ioError(EPERM, path: file.path)
        }
        guard Darwin.fchmod(fd, mode_t(0o600)) == 0 else { throw ioError(errno, path: file.path) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw ioError(code, path: file.path)
        }
        ownsDescriptor = false
        return InstanceLock(descriptor: fd)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }

    private static func ioError(_ code: Int32, path: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
            NSFilePathErrorKey: path,
            NSLocalizedDescriptionKey: "无法取得逐光的独占运行锁：\(String(cString: strerror(code)))"
        ])
    }
}
