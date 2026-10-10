import CryptoKit
import Foundation

/// RFC 7636 Proof Key for Code Exchange, S256 method.
struct PKCE: Equatable {
    let verifier: String
    let challenge: String

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    /// 32 random bytes -> 43-character base64url verifier (within the 43...128 the RFC requires).
    static func generate() -> PKCE {
        PKCE(verifier: base64URL(randomBytes(32)))
    }

    /// `BASE64URL(SHA256(ASCII(verifier)))`.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// Opaque anti-CSRF value echoed back on the callback URL.
    static func randomState() -> String {
        base64URL(randomBytes(16))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
