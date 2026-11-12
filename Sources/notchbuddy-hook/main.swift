// Agent hook: forwards the stdin JSON to Notch Buddy over its Unix socket and prints the reply.
// Usage: notchbuddy-hook [--agent <id>] [--event <Name>] [--wait <seconds>] [--default <json>]   (no --agent = Claude Code)
// --default is printed when there is no decision (app not running or nothing to say); some agents require JSON output.
// Never blocks the agent when the app is not running: no socket → exit 0 with no output (normal flow).
import Foundation

let args = CommandLine.arguments
func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
let agent = arg("--agent") ?? "claude-code"
let input = FileHandle.standardInput.readDataToEndOfFile()
let path = NSHomeDirectory() + "/Library/Application Support/NotchBuddy/hook.sock"
// Only events that wait for the user (Claude's PermissionRequest, or --wait) block; stay under the agent's hook timeout.
let waitSeconds = arg("--wait").flatMap(Int.init)
    ?? (agent == "claude-code" && input.range(of: Data(#""PermissionRequest""#.utf8)) != nil ? 590 : 2)

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
/// Records hooks that ran but couldn't reach the app (not running, or blocked by an agent's sandbox), so a silent
/// agent can be told apart from one that never runs the hook. Metadata only: time, agent, event, error.
func noteFailure(_ why: String) {
    let path = NSHomeDirectory() + "/Library/Logs/NotchBuddy/hook-failures.log"
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size > 256_000 { try? FileManager.default.removeItem(atPath: path) }
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(agent) \(arg("--event") ?? "-") \(why)\n"
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { FileManager.default.createFile(atPath: path, contents: Data(line.utf8), attributes: [.posixPermissions: 0o600]) }
}

func finish(_ reply: Data) -> Never {
    FileHandle.standardOutput.write(reply.isEmpty ? Data((arg("--default") ?? "").utf8) : reply)
    exit(0)
}
guard fd >= 0 else { noteFailure("socket errno=\(errno)"); finish(Data()) }
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
if !connected { noteFailure("connect errno=\(errno)") }
guard connected else { finish(Data()) }

// Where a Claude Code session runs (cli, claude-vscode, claude-desktop…), so the notch can label it.
let entry = (ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"] ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" }
let event = (arg("--event") ?? "").filter { $0.isLetter }
/// The terminal the agent runs in: the first ancestor process with a controlling tty (hooks themselves have piped stdio).
func ancestorTTY() -> String {
    var pid = getppid()
    for _ in 0..<10 where pid > 1 {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return "" }
        let dev = info.kp_eproc.e_tdev
        if dev != -1, let name = devname(dev, S_IFCHR) { return "/dev/" + String(cString: name) }
        pid = info.kp_eproc.e_ppid
    }
    return ""
}
let tty = ancestorTTY()
let message = Data("NB1 agent=\(agent) entry=\(entry) event=\(event)\(tty.isEmpty ? "" : " tty=\(tty)")\n".utf8) + input
_ = message.withUnsafeBytes { buf -> Bool in
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
finish(reply)
