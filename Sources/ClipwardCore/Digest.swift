import CommonCrypto
import Foundation

/// SHA-256 helpers built on CommonCrypto (available on every supported macOS).
public enum Digest {
    /// Hex-encoded SHA-256 of the concatenated `parts`, each prefixed with its length
    /// so that ("ab", "c") and ("a", "bc") hash differently.
    public static func sha256Hex(_ parts: [Data]) -> String {
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        for part in parts {
            var length = UInt64(part.count).bigEndian
            withUnsafeBytes(of: &length) { _ = CC_SHA256_Update(&context, $0.baseAddress, CC_LONG($0.count)) }
            part.withUnsafeBytes { _ = CC_SHA256_Update(&context, $0.baseAddress, CC_LONG(part.count)) }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
