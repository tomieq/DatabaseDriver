import Foundation

struct SHA1 {
    static func hash(data: Data) -> Data {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var message = [UInt8](data)
        let originalLengthBits = UInt64(message.count) * 8
        // append 0x80
        message.append(0x80)
        // pad with zeros until length ≡ 56 mod 64
        while (message.count % 64) != 56 { message.append(0) }
        // append length big-endian
        var lenBE = originalLengthBits.bigEndian
        withUnsafeBytes(of: &lenBE) { ptr in
            message.append(contentsOf: ptr)
        }

        let chunks = message.count / 64
        for i in 0..<chunks {
            var w = [UInt32](repeating: 0, count: 80)
            for t in 0..<16 {
                let base = i * 64 + t * 4
                w[t] = (UInt32(message[base]) << 24) | (UInt32(message[base + 1]) << 16) | (UInt32(message[base + 2]) << 8) | UInt32(message[base + 3])
            }
            for t in 16..<80 { w[t] = self.leftrotate(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], by: 1) }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4

            for t in 0..<80 {
                var f: UInt32 = 0
                var k: UInt32 = 0
                if t < 20 {
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                } else if t < 40 {
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                } else if t < 60 {
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                } else {
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = self.leftrotate(a, by: 5) &+ f &+ e &+ k &+ w[t]
                e = d
                d = c
                c = self.leftrotate(b, by: 30)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        var digest = Data()
        [h0, h1, h2, h3, h4].forEach { v in
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { digest.append(contentsOf: $0) }
        }
        return digest
    }

    private static func leftrotate(_ value: UInt32, by: UInt32) -> UInt32 {
        return (value << by) | (value >> (32 - by))
    }
}
