import BigInt
import Foundation
#if canImport(Security)
import Security
#endif

enum CachingSHA2Password {
    static let requestPublicKey: UInt8 = 0x02
    static let fastAuthSuccess: UInt8 = 0x03
    static let performFullAuthentication: UInt8 = 0x04

    static func plaintextPassword(_ password: String) -> Data {
        var data = Data(password.utf8)
        data.append(0)
        return data
    }

    static func encryptedPassword(_ password: String, scramble: Data, publicKeyPEM: Data) throws -> Data {
        let message = self.obfuscatedPassword(password, scramble: scramble)
        #if canImport(Security)
        let der = try PEMDocument.decode(publicKeyPEM)
        if let encrypted = try SecurityRSA.encrypt(message, publicKeyDER: der) {
            return encrypted
        }
        #endif
        let key = try RSAPublicKey(pem: publicKeyPEM)
        return try RSAOAEP.encrypt(message, using: key)
    }

    static func obfuscatedPassword(_ password: String, scramble: Data) -> Data {
        var data = self.plaintextPassword(password)
        guard !scramble.isEmpty else { return data }
        for index in 0..<data.count {
            data[index] ^= scramble[index % scramble.count]
        }
        return data
    }
}

private struct RSAPublicKey {
    let modulus: BigUInt
    let exponent: BigUInt
    let modulusLength: Int

    init(modulus: BigUInt, exponent: BigUInt, modulusLength: Int) {
        self.modulus = modulus
        self.exponent = exponent
        self.modulusLength = modulusLength
    }

    init(pem: Data) throws {
        let der = try PEMDocument.decode(pem)
        if PEMDocument.containsHeader("BEGIN RSA PUBLIC KEY", in: pem) {
            self = try Self.parseRSAPublicKey(der)
        } else {
            self = try Self.parseSubjectPublicKeyInfo(der)
        }
    }

    private static func parseSubjectPublicKeyInfo(_ der: Data) throws -> Self {
        var reader = DERReader(data: der)
        var sequence = try reader.readConstructed(tag: 0x30)
        _ = try sequence.readConstructed(tag: 0x30)
        let bitString = try sequence.readPrimitive(tag: 0x03)
        guard let unusedBits = bitString.first, unusedBits == 0 else {
            throw ConnectionError.protocolError("invalid RSA public key")
        }
        return try Self.parseRSAPublicKey(Data(bitString.dropFirst()))
    }

    private static func parseRSAPublicKey(_ der: Data) throws -> Self {
        var reader = DERReader(data: der)
        var sequence = try reader.readConstructed(tag: 0x30)
        let modulusData = try sequence.readInteger()
        let exponentData = try sequence.readInteger()
        let modulus = BigUInt(modulusData)
        let exponent = BigUInt(exponentData)
        guard modulus > 0, exponent > 0 else {
            throw ConnectionError.protocolError("invalid RSA public key")
        }
        return Self(modulus: modulus, exponent: exponent, modulusLength: modulusData.count)
    }
}

private enum RSAOAEP {
    private static let hashLength = 20
    private static let labelHash = SHA1.hash(data: Data())

    static func encrypt(_ message: Data, using key: RSAPublicKey) throws -> Data {
        let encodedMessage = try self.encode(message, modulusLength: key.modulusLength)
        let messageInt = BigUInt(encodedMessage)
        guard messageInt < key.modulus else {
            throw ConnectionError.protocolError("RSA message out of range")
        }
        let encryptedInt = self.modularExponentiation(messageInt, exponent: key.exponent, modulus: key.modulus)
        let encrypted = encryptedInt.serialize()
        if encrypted.count == key.modulusLength {
            return encrypted
        }
        let padding = Data(repeating: 0, count: key.modulusLength - encrypted.count)
        return padding + encrypted
    }

    private static func encode(_ message: Data, modulusLength: Int) throws -> Data {
        guard message.count <= modulusLength - (2 * self.hashLength) - 2 else {
            throw ConnectionError.protocolError("password is too long for server RSA key")
        }

        let paddingCount = modulusLength - message.count - (2 * self.hashLength) - 2
        let dataBlock = self.labelHash
            + Data(repeating: 0, count: paddingCount)
            + Data([0x01])
            + message

        var generator = SystemRandomNumberGenerator()
        let seed = Data((0..<self.hashLength).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
        let dbMask = self.maskGenerationFunction(seed: seed, outputLength: modulusLength - self.hashLength - 1)
        let maskedDataBlock = self.xor(dataBlock, with: dbMask)
        let seedMask = self.maskGenerationFunction(seed: maskedDataBlock, outputLength: self.hashLength)
        let maskedSeed = self.xor(seed, with: seedMask)

        var encoded = Data([0x00])
        encoded.append(maskedSeed)
        encoded.append(maskedDataBlock)
        return encoded
    }

    private static func modularExponentiation(_ base: BigUInt, exponent: BigUInt, modulus: BigUInt) -> BigUInt {
        var result = BigUInt(1)
        var factor = base % modulus
        var remainingExponent = exponent

        while remainingExponent > 0 {
            if remainingExponent % 2 == 1 {
                result = (result * factor) % modulus
            }
            remainingExponent /= 2
            if remainingExponent > 0 {
                factor = (factor * factor) % modulus
            }
        }

        return result
    }

    private static func maskGenerationFunction(seed: Data, outputLength: Int) -> Data {
        var output = Data()
        var counter: UInt32 = 0

        while output.count < outputLength {
            var block = seed
            block.append(UInt8((counter >> 24) & 0xFF))
            block.append(UInt8((counter >> 16) & 0xFF))
            block.append(UInt8((counter >> 8) & 0xFF))
            block.append(UInt8(counter & 0xFF))
            output.append(SHA1.hash(data: block))
            counter &+= 1
        }

        return output.prefix(outputLength)
    }

    private static func xor(_ lhs: Data, with rhs: Data) -> Data {
        Data(zip(lhs, rhs).map(^))
    }
}

#if canImport(Security)
private enum SecurityRSA {
    static func encrypt(_ message: Data, publicKeyDER: Data) throws -> Data? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: publicKeyDER.count * 8
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(publicKeyDER as CFData, attributes as CFDictionary, &error) else {
            if let error {
                let errorDescription = CFErrorCopyDescription(error.takeRetainedValue()) as String
                throw ConnectionError.protocolError("failed to parse server RSA key: \(errorDescription)")
            }
            return nil
        }

        let algorithm = SecKeyAlgorithm.rsaEncryptionOAEPSHA1
        guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm) else {
            return nil
        }

        guard let encrypted = SecKeyCreateEncryptedData(key, algorithm, message as CFData, &error) else {
            if let error {
                let errorDescription = CFErrorCopyDescription(error.takeRetainedValue()) as String
                throw ConnectionError.protocolError("failed to encrypt password: \(errorDescription)")
            }
            throw ConnectionError.protocolError("failed to encrypt password")
        }

        return encrypted as Data
    }
}
#endif

private struct PEMDocument {
    static func containsHeader(_ header: String, in data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(header)
    }

    static func decode(_ data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            if data.first == 0x30 {
                return data
            }
            throw ConnectionError.protocolError("server returned a non-UTF8 public key")
        }

        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") && !$0.isEmpty }
        let base64 = lines.joined()
        guard let der = Data(base64Encoded: base64) else {
            throw ConnectionError.protocolError("server returned an invalid public key")
        }
        return der
    }
}

private struct DERReader {
    private let data: Data
    private var index: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readConstructed(tag: UInt8) throws -> DERReader {
        let bytes = try self.readPrimitive(tag: tag)
        return DERReader(data: bytes)
    }

    mutating func readInteger() throws -> Data {
        let integer = try self.readPrimitive(tag: 0x02)
        guard !integer.isEmpty else {
            throw ConnectionError.protocolError("invalid RSA public key")
        }
        if integer.count > 1, integer.first == 0 {
            return Data(integer.dropFirst())
        }
        return integer
    }

    mutating func readPrimitive(tag: UInt8) throws -> Data {
        guard self.index < self.data.count else {
            throw ConnectionError.protocolError("truncated DER data")
        }
        let actualTag = self.data[self.index]
        self.index += 1
        guard actualTag == tag else {
            throw ConnectionError.protocolError("unexpected DER tag")
        }
        let length = try self.readLength()
        guard self.index + length <= self.data.count else {
            throw ConnectionError.protocolError("truncated DER data")
        }
        let value = self.data[self.index..<(self.index + length)]
        self.index += length
        return Data(value)
    }

    private mutating func readLength() throws -> Int {
        guard self.index < self.data.count else {
            throw ConnectionError.protocolError("truncated DER data")
        }
        let firstByte = self.data[self.index]
        self.index += 1
        if firstByte & 0x80 == 0 {
            return Int(firstByte)
        }
        let byteCount = Int(firstByte & 0x7F)
        guard byteCount > 0, byteCount <= 4, self.index + byteCount <= self.data.count else {
            throw ConnectionError.protocolError("invalid DER length")
        }
        var length = 0
        for _ in 0..<byteCount {
            length = (length << 8) | Int(self.data[self.index])
            self.index += 1
        }
        return length
    }
}