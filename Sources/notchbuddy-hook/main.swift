// Claude Code hook: forwards the stdin JSON to Notch Buddy over its Unix socket and prints the reply.
// Never blocks Claude when the app is not running: no socket → exit 0 with no output (normal flow).
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let path = NSHomeDirectory() + "/Library/Application Support/NotchBuddy/hook.sock"
// Only a PermissionRequest waits for the user; keep under the 600 s hook timeout set in settings.json.
let waitSeconds = input.range(of: Data(#""PermissionRequest""#.utf8)) != nil ? 590 : 2

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var on: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
var rcv = timeval(tv_sec: waitSeconds, tv_usec: 0), snd = timeval(tv_sec: 2, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcv, socklen_t(MemoryLayout<timeval>.size))
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &snd, socklen_t(MemoryLayout<timeval>.size))

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let ok = withUnsafeMutableBytes(of: &addr.sun_path) { buf -> Bool in
    let bytes = Array(path.utf8)
    guard bytes.count < buf.count else { return false }
    buf.copyBytes(from: bytes); buf[bytes.count] = 0
    return true
}
let connected = ok && withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
}
guard connected else { exit(0) }

_ = input.withUnsafeBytes { buf -> Bool in
    var off = 0
    while off < buf.count {
        let n = write(fd, buf.baseAddress! + off, buf.count - off)
        if n <= 0 { return false }
        off += n
    }
    return true
}
shutdown(fd, SHUT_WR)

var reply = Data()
var chunk = [UInt8](repeating: 0, count: 4096)
while true {
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { break }
    reply.append(chunk, count: n)
}
close(fd)
FileHandle.standardOutput.write(reply)
exit(0)
