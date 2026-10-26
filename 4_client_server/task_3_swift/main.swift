#if canImport(Glibc)
import Glibc
let sockStream = Int32(SOCK_STREAM.rawValue)
#else
import Darwin
let sockStream = SOCK_STREAM
#endif
import Foundation

final class LineReader {
    private let fd: Int32
    private var buffer = [UInt8]()

    init(fd: Int32) { self.fd = fd }

    func readLine() -> String? {
        while true {
            if let i = buffer.firstIndex(of: 10) {
                let line = Array(buffer[..<i])
                buffer.removeSubrange(...i)
                return String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var chunk = [UInt8](repeating: 0, count: 1024)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }
}

func sendLine(_ fd: Int32, _ text: String) {
    let bytes = Array((text + "\n").utf8)
    _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
}

final class Scoreboard {
    private let lock = NSLock()
    private var score = 0
    private var clients: [Int32: String] = [:]

    func join(_ fd: Int32, name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        clients[fd] = name
        broadcastLocked("\(name) joined, players online: \(clients.count)")
        return score
    }

    func leave(_ fd: Int32) {
        lock.lock(); defer { lock.unlock() }
        guard let name = clients.removeValue(forKey: fd) else { return }
        broadcastLocked("\(name) left, players online: \(clients.count)")
    }

    func change(by delta: Int, from name: String) {
        lock.lock(); defer { lock.unlock() }
        score += delta
        let sign = delta >= 0 ? "+" : ""
        broadcastLocked("\(name): \(sign)\(delta) -> score \(score)")
    }

    func current() -> Int {
        lock.lock(); defer { lock.unlock() }
        return score
    }

    private func broadcastLocked(_ message: String) {
        print("[broadcast] \(message)")
        for fd in clients.keys { sendLine(fd, message) }
    }
}

func handleClient(fd: Int32, name: String, board: Scoreboard) {
    let reader = LineReader(fd: fd)
    let score = board.join(fd, name: name)
    sendLine(fd, "Welcome, you are \(name). Current score: \(score). Commands: +N, -N, GET, QUIT")

    while let line = reader.readLine() {
        if line.isEmpty { continue }
        if line.uppercased() == "QUIT" { break }
        if line.uppercased() == "GET" {
            sendLine(fd, "Score: \(board.current())")
        } else if (line.hasPrefix("+") || line.hasPrefix("-")), let delta = Int(line) {
            board.change(by: delta, from: name)
        } else {
            sendLine(fd, "Error: unknown command '\(line)'. Use +N, -N, GET or QUIT")
        }
    }
    board.leave(fd)
    close(fd)
}

func runServer(port: UInt16) {
    let server = socket(AF_INET, sockStream, 0)
    var yes: Int32 = 1
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = in_addr_t(0)
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0, listen(server, 16) == 0 else {
        print("Cannot listen on port \(port)")
        exit(1)
    }
    print("Score server on port \(port)")

    let board = Scoreboard()
    var counter = 0
    while true {
        var clientAddr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let fd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(server, $0, &length) }
        }
        if fd < 0 { continue }
        counter += 1
        let name = "player\(counter)"
        let host = String(cString: inet_ntoa(clientAddr.sin_addr))
        print("Connected \(name) from \(host):\(UInt16(bigEndian: clientAddr.sin_port))")
        Thread { handleClient(fd: fd, name: name, board: board) }.start()
    }
}

func runClient(host: String, port: UInt16) {
    let fd = socket(AF_INET, sockStream, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    inet_pton(AF_INET, host, &addr.sin_addr)
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connected == 0 else {
        print("Cannot connect to \(host):\(port)")
        exit(1)
    }

    Thread {
        let reader = LineReader(fd: fd)
        while let line = reader.readLine() { print(line) }
        print("Connection closed")
        exit(0)
    }.start()

    while let line = Swift.readLine() {
        sendLine(fd, line)
        if line.uppercased() == "QUIT" { break }
    }
    usleep(300_000)
    close(fd)
}

signal(SIGPIPE, SIG_IGN)
setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "server":
    runServer(port: UInt16(args.count > 2 ? args[2] : "9090") ?? 9090)
case "client":
    runClient(host: args.count > 2 ? args[2] : "127.0.0.1",
              port: UInt16(args.count > 3 ? args[3] : "9090") ?? 9090)
default:
    print("Usage: score server [port] | score client [host] [port]")
}
