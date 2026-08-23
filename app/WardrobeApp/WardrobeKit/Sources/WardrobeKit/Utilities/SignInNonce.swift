import CryptoKit
import Foundation

public enum SignInNonce {
    public static func make() -> String {
        hexadecimal((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })
    }

    public static func hashed(_ nonce: String) -> String {
        hexadecimal(Array(SHA256.hash(data: Data(nonce.utf8))))
    }

    private static func hexadecimal(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
