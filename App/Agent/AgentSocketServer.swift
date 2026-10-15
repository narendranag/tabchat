import Darwin
import Foundation

/// A Unix socket that accepts one request line per connection and writes one reply line.
/// The socket file is mode 0600, and each peer's user id is checked, so only the owner's own
/// processes get in. Calls arrive off the main thread; the handler hops to wherever it needs.
final class AgentSocketServer: @unchecked Sendable {
    /// Request line and the peer's process name in; reply line out.
    typealias Handler = @Sendable (Data, String) async -> Data

    private let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.narendranag.tabchat.agent-socket")
    // Touched only on `queue` after `start`.
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(url: URL, handler: @escaping Handler) {
        path = url.path
        self.handler = handler
    }

    enum StartError: Error {
        case pathTooLong
        case system(String, Int32)
    }

    func start() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        removeStaleSocket()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.system("socket", errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw StartError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        // Created owner-only from the start, so there is no moment when others could connect.
        let previous = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(previous)
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw StartError.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw StartError.system("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        queue.sync {
            listener = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptPending() }
            source.setCancelHandler { close(fd) }
            self.source = source
            source.resume()
        }
    }

    func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            listener = -1
        }
        unlink(path)
    }

    /// Only a leftover socket is removed; any other kind of file at the path is left alone (bind then fails).
    private func removeStaleSocket() {
        var info = stat()
        if lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK {
            unlink(path)
        }
    }

    private func acceptPending() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            serve(client)
        }
    }

    private func serve(_ client: Int32) {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
            close(client)
            return
        }
        // BSD hands the listener's O_NONBLOCK to accepted sockets; reads here must wait (with a timeout).
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let peer = Self.peerName(client)
        let handler = handler
        Thread.detachNewThread {
            let request = Self.readLine(client)
            Task.detached {
                let reply = await handler(request, peer)
                Self.writeAll(client, reply)
                close(client)
            }
        }
    }

    /// Bytes up to the first newline, at most `AgentWire.maxRequestBytes`.
    private static func readLine(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= AgentWire.maxRequestBytes {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0 ..< count])
            if let newline = data.firstIndex(of: 0x0A) {
                return data[data.startIndex ..< newline]
            }
        }
        return data
    }

    private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var left = buffer.count
            while left > 0 {
                let written = write(fd, pointer, left)
                guard written > 0 else { return }
                pointer += written
                left -= written
            }
        }
    }

    /// The connecting process's name, for the call log ("tabchat-agent", "python3").
    private static func peerName(_ fd: Int32) -> String {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return "unknown" }
        var name = [UInt8](repeating: 0, count: 256)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return "pid \(pid)" }
        let process = String(bytes: name.prefix { $0 != 0 }, encoding: .utf8) ?? "pid"
        return "\(process) (\(pid))"
    }
}
