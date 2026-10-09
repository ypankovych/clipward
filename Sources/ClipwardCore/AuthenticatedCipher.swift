import CommonCrypto
import Foundation
import Security

public enum CipherError: Error {
    case invalidKeyLength
    case randomGenerationFailed(OSStatus)
    case cryptFailed(CCCryptorStatus)
    case malformedInput
    case authenticationFailed
}

/// Authenticated encryption: AES-256-CBC with HMAC-SHA256 over the IV and ciphertext
/// (encrypt-then-MAC).
///
/// CommonCrypto is used instead of CryptoKit because CryptoKit requires macOS 10.15.
/// Sealed layout: `version (1) | IV (16) | ciphertext | HMAC (32)`.
public struct AuthenticatedCipher {
    /// 32 bytes of AES key followed by 32 bytes of HMAC key.
    public static let keyLength = 64

    private static let version: UInt8 = 1
    private static let ivLength = kCCBlockSizeAES128
    private static let macLength = Int(CC_SHA256_DIGEST_LENGTH)

    private let encryptionKey: Data
    private let macKey: Data

    /// - Parameter key: `keyLength` random bytes.
    public init(key: Data) throws {
        guard key.count == Self.keyLength else { throw CipherError.invalidKeyLength }
        encryptionKey = key.subdata(in: 0..<32)
        macKey = key.subdata(in: 32..<64)
    }

    /// Encrypts and authenticates `plaintext`.
    public func seal(_ plaintext: Data) throws -> Data {
        let iv = try Self.randomBytes(count: Self.ivLength)
        let ciphertext = try crypt(CCOperation(kCCEncrypt), plaintext, iv: iv)
        var sealed = Data([Self.version])
        sealed.append(iv)
        sealed.append(ciphertext)
        sealed.append(mac(sealed))
        return sealed
    }

    /// Verifies and decrypts data produced by `seal`.
    /// - Throws: `CipherError.authenticationFailed` if the data was tampered with or the key differs.
    public func open(_ sealed: Data) throws -> Data {
        let sealed = Data(sealed) // re-base indices to zero
        let minimumLength = 1 + Self.ivLength + kCCBlockSizeAES128 + Self.macLength
        guard sealed.count >= minimumLength, sealed[0] == Self.version else { throw CipherError.malformedInput }

        let macStart = sealed.count - Self.macLength
        let body = sealed.subdata(in: 0..<macStart)
        guard Self.constantTimeEquals(mac(body), sealed.subdata(in: macStart..<sealed.count)) else {
            throw CipherError.authenticationFailed
        }
        let iv = body.subdata(in: 1..<(1 + Self.ivLength))
        let ciphertext = body.subdata(in: (1 + Self.ivLength)..<body.count)
        return try crypt(CCOperation(kCCDecrypt), ciphertext, iv: iv)
    }

    /// Cryptographically secure random bytes.
    public static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw CipherError.randomGenerationFailed(status) }
        return bytes
    }

    private func crypt(_ operation: CCOperation, _ input: Data, iv: Data) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var produced = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inBytes in
                iv.withUnsafeBytes { ivBytes in
                    encryptionKey.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, encryptionKey.count, ivBytes.baseAddress,
                            inBytes.baseAddress, input.count, out.baseAddress, outputCapacity, &produced
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CipherError.cryptFailed(status) }
        output.count = produced
        return output
    }

    private func mac(_ data: Data) -> Data {
        var result = Data(count: Self.macLength)
        result.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { bytes in
                macKey.withUnsafeBytes { key in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), key.baseAddress, macKey.count,
                           bytes.baseAddress, data.count, out.baseAddress)
                }
            }
        }
        return result
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { difference |= a ^ b }
        return difference == 0
    }
}
