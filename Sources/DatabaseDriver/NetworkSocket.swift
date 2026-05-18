import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private enum SystemSocket {
    static func connect(_ socket: Int32, _ address: UnsafePointer<sockaddr>, _ addressLength: socklen_t) -> Int32 {
        #if os(Linux)
        Glibc.connect(socket, address, addressLength)
        #else
        Darwin.connect(socket, address, addressLength)
        #endif
    }

    static func close(_ fd: Int32) -> Int32 {
        #if os(Linux)
        Glibc.close(fd)
        #else
        Darwin.close(fd)
        #endif
    }
}

final class NetworkSocket {
    private var fd: Int32 = -1
    private let debug: Bool = ProcessInfo.processInfo.environment["MYSQLPROTO_DEBUG"] == "1"

    init() throws {}

    func connect(host: String, port: Int) throws {
        let addrInfo = try resolve(host: host, port: port)
        var sockfd: Int32 = -1
        var ptr: UnsafeMutablePointer<addrinfo>? = addrInfo
        while ptr != nil {
            let ai = ptr!.pointee
            sockfd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
            if sockfd == -1 {
                ptr = ai.ai_next
                continue
            }
            let res = SystemSocket.connect(sockfd, ai.ai_addr, ai.ai_addrlen)
            if res == 0 {
                self.fd = sockfd
                freeaddrinfo(addrInfo)
                return
            }
            _ = SystemSocket.close(sockfd)
            ptr = ai.ai_next
        }
        freeaddrinfo(addrInfo)
        let err = errno
        let msg = String(cString: strerror(err))
        if self.debug { print("[netsock] connect failed fd=\(self.fd) errno=\(err) msg=\(msg)") }
        throw NSError(domain: "NetworkSocket", code: Int(err == 0 ? 1 : err), userInfo: [NSLocalizedDescriptionKey: "connect failed: \(msg)"])
    }

    func readExactly(_ count: Int) throws -> Data {
        var remaining = count
        var buffer = Data()
        buffer.reserveCapacity(count)
        while remaining > 0 {
            var chunk = [UInt8](repeating: 0, count: remaining)
            let n = recv(fd, &chunk, remaining, 0)
            if n <= 0 {
                let err = errno
                let msg = String(cString: strerror(err))
                if self.debug { print("[netsock] recv fd=\(self.fd) returned \(n) errno=\(err) msg=\(msg)") }
                throw NSError(domain: "NetworkSocket", code: Int(err == 0 ? 2 : err), userInfo: [NSLocalizedDescriptionKey: msg])
            }
            buffer.append(chunk, count: n)
            remaining -= n
        }
        return buffer
    }

    func readSome(min: Int = 1) throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = recv(fd, &chunk, chunk.count, 0)
        if n <= 0 {
            let err = errno
            let msg = String(cString: strerror(err))
            if self.debug { print("[netsock] recvSome fd=\(self.fd) returned \(n) errno=\(err) msg=\(msg)") }
            throw NSError(domain: "NetworkSocket", code: Int(err == 0 ? 2 : err), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return Data(chunk[0..<n])
    }

    func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < data.count {
                let n = send(fd, ptr.baseAddress!.advanced(by: sent), data.count - sent, 0)
                if n <= 0 {
                    let err = errno
                    let msg = String(cString: strerror(err))
                    if self.debug { print("[netsock] send fd=\(self.fd) wrote \(n) errno=\(err) msg=\(msg)") }
                    throw NSError(domain: "NetworkSocket", code: Int(err == 0 ? 3 : err), userInfo: [NSLocalizedDescriptionKey: msg])
                }
                sent += n
            }
        }
    }

    func close() throws {
        if self.fd != -1 { _ = SystemSocket.close(self.fd); self.fd = -1 }
    }

    private func resolve(host: String, port: Int) throws -> UnsafeMutablePointer<addrinfo> {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let res = getaddrinfo(host, portStr, &hints, &infoPtr)
        if res != 0 || infoPtr == nil { throw NSError(domain: "NetworkSocket", code: Int(res), userInfo: nil) }
        return infoPtr!
    }
}
