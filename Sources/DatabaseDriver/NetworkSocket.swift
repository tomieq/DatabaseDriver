import Foundation

final class NetworkSocket {
    private var fd: Int32 = -1

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
            let res = Darwin.connect(sockfd, ai.ai_addr, ai.ai_addrlen)
            if res == 0 {
                self.fd = sockfd
                freeaddrinfo(addrInfo)
                return
            }
            Darwin.close(sockfd)
            ptr = ai.ai_next
        }
        freeaddrinfo(addrInfo)
        throw NSError(domain: "NetworkSocket", code: 1, userInfo: [NSLocalizedDescriptionKey: "connect failed"])
    }

    func readExactly(_ count: Int) throws -> Data {
        var remaining = count
        var buffer = Data()
        buffer.reserveCapacity(count)
        while remaining > 0 {
            var chunk = [UInt8](repeating: 0, count: remaining)
            let n = recv(fd, &chunk, remaining, 0)
            if n <= 0 { throw NSError(domain: "NetworkSocket", code: 2, userInfo: nil) }
            buffer.append(chunk, count: n)
            remaining -= n
        }
        return buffer
    }

    func readSome(min: Int = 1) throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = recv(fd, &chunk, chunk.count, 0)
        if n <= 0 { throw NSError(domain: "NetworkSocket", code: 2, userInfo: nil) }
        return Data(chunk[0..<n])
    }

    func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < data.count {
                let n = send(fd, ptr.baseAddress!.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { throw NSError(domain: "NetworkSocket", code: 3, userInfo: nil) }
                sent += n
            }
        }
    }

    func close() throws {
        if self.fd != -1 { Darwin.close(self.fd); self.fd = -1 }
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
