import XCTest
@testable import FreeTrack

final class PKCETests: XCTestCase {
    /// RFC 7636 appendix B: the S256 challenge for the reference verifier.
    func testRFC7636AppendixBVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(PKCE(verifier: verifier).challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifierShape() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<20 {
            let pkce = PKCE.generate()
            XCTAssertEqual(pkce.verifier.count, 43)
            XCTAssertTrue(pkce.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
            XCTAssertEqual(pkce.challenge.count, 43)
            XCTAssertFalse(pkce.challenge.contains("="))
            XCTAssertFalse(pkce.challenge.contains("+"))
            XCTAssertFalse(pkce.challenge.contains("/"))
            XCTAssertEqual(pkce.challenge, PKCE.challenge(for: pkce.verifier))
        }
    }

    func testVerifiersAreUnique() {
        let set = Set((0..<50).map { _ in PKCE.generate().verifier })
        XCTAssertEqual(set.count, 50)
    }

    func testBase64URLDropsPaddingAndUsesURLAlphabet() {
        // 0xFB 0xFF -> standard base64 "+/8=" ; base64url "-_8"
        XCTAssertEqual(PKCE.base64URL(Data([0xFB, 0xFF])), "-_8")
        XCTAssertEqual(PKCE.base64URL(Data()), "")
    }

    func testCallbackParsing() throws {
        let state = "abc123XYZ_-"
        let ok = URL(string: "freetrack://auth/callback?code=one-time&state=\(state)")!
        XCTAssertEqual(try WebOAuthFlow.parseCallback(ok, expectedState: state), "one-time")

        let wrongState = URL(string: "freetrack://auth/callback?code=one-time&state=other")!
        XCTAssertThrowsError(try WebOAuthFlow.parseCallback(wrongState, expectedState: state)) { error in
            XCTAssertEqual(error as? AccountError, .stateMismatch)
        }

        let cancelled = URL(string: "freetrack://auth/callback?error=cancelled&state=\(state)")!
        XCTAssertThrowsError(try WebOAuthFlow.parseCallback(cancelled, expectedState: state)) { error in
            XCTAssertEqual(error as? AccountError, .cancelled)
        }

        let wrongScheme = URL(string: "https://example.com/auth/callback?code=x&state=\(state)")!
        XCTAssertThrowsError(try WebOAuthFlow.parseCallback(wrongScheme, expectedState: state))
    }
}
