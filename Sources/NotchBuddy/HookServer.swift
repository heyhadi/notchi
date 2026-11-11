import Foundation
import NotchBuddyCore

/// Unix-socket server the hook binary talks to. Socket lives in a 0700 folder and is itself 0600,
/// and only peers running as the same user are accepted.
final class HookServer: @unchecked Sendable {
    static let directory = NSHomeDirectory() + "/Library/Application Support/NotchBuddy"
    static let socketPath = directory + "/hook.sock"

    /// Called on the main queue. Call `respond` exactly once: nil = no decision (Claude Code shows its own prompt).
    var onEvent: (@MainActor (HookEvent, _ respond: @escaping @Sendable (Data?) -> Void) -> Void)?

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "NotchBuddy.HookServer", attributes: .concurrent)

    func start() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directory)
        unlink(Self.socketPath)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.EIO) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let bytes = Array(Self.socketPath.utf8)
            buf.copyBytes(from: bytes.prefix(buf.count - 1)); buf[min(bytes.count, buf.count - 1)] = 0
        }
        let old = umask(0o177) // socket file created as 0600
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(old)
        guard bound == 0, chmod(Self.socketPath, 0o600) == 0, listen(listenFD, 16) == 0 else {
            close(listenFD); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    private func acceptOne() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        queue.async { [weak self] in
            var data = Data()
            var chunk = [UInt8](repeating: 0, count: 8192)
            while data.count < 4 << 20 { // cap payload at 4 MB
                let n = read(fd, &chunk, chunk.count)
                if n <= 0 { break }
                data.append(chunk, count: n)
            }
            guard let event = HookEvent.parse(message: data) else { close(fd); return }
            let once = Once()
            let respond: @Sendable (Data?) -> Void = { reply in
                guard once.claim() else { return }
                if let reply { _ = reply.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } }
                close(fd)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let handler = self?.onEvent { handler(event, respond) } else { respond(nil) }
                }
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
