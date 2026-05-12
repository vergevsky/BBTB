import XCTest
@testable import ConfigParser

/// PROTO-05 — Hysteria2 (hy2:// + hysteria2://) URI parser tests.
///
/// Plan 04-04 GREEN — реализованы Hysteria2URIParser + D-08 (insecure→allowInsecure)
/// + D-09 (dual scheme + multi-port reject) + obfs whitelist.
final class Hysteria2URIParserTests: XCTestCase {

    private func loadFixture(_ name: String, ext: String = "txt") -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).\(ext)")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: D-09 — оба URI scheme aliases работают

    func test_bothSchemes_parse() throws {
        let hy2 = "hy2://AuthPass@example.com:443?sni=example.com#Server"
        let hysteria2 = "hysteria2://AuthPass@example.com:443?sni=example.com#Server"
        let a = try Hysteria2URIParser.parse(hy2)
        let b = try Hysteria2URIParser.parse(hysteria2)
        XCTAssertEqual(a.host, b.host)
        XCTAssertEqual(a.port, b.port)
        XCTAssertEqual(a.auth, b.auth)
        XCTAssertEqual(a.sni, b.sni)
        XCTAssertEqual(a.host, "example.com")
        XCTAssertEqual(a.port, 443)
        XCTAssertEqual(a.auth, "AuthPass")
        XCTAssertEqual(a.sni, "example.com")
        XCTAssertEqual(a.remarks, "Server")
    }

    // MARK: D-08 — insecure=1 / allowInsecure=1 / skip-cert-verify=1 → allowInsecure=true

    func test_insecureFlag_setsAllowInsecure() throws {
        // Все три синонима независимо триггерят allowInsecure=true.
        let u1 = "hy2://auth@host.example:443?sni=host.example&insecure=1"
        let u2 = "hy2://auth@host.example:443?sni=host.example&allowInsecure=1"
        let u3 = "hy2://auth@host.example:443?sni=host.example&skip-cert-verify=1"
        // Без ни одного из этих flags → allowInsecure=false (strict TLS по умолчанию).
        let u4 = "hy2://auth@host.example:443?sni=host.example"

        XCTAssertTrue(try Hysteria2URIParser.parse(u1).allowInsecure, "insecure=1 should set allowInsecure")
        XCTAssertTrue(try Hysteria2URIParser.parse(u2).allowInsecure, "allowInsecure=1 should set allowInsecure")
        XCTAssertTrue(try Hysteria2URIParser.parse(u3).allowInsecure, "skip-cert-verify=1 should set allowInsecure")
        XCTAssertFalse(try Hysteria2URIParser.parse(u4).allowInsecure, "no flag → allowInsecure=false (strict default)")
    }

    // MARK: D-08 — fixture с insecure=1 → allowInsecure=true

    func test_insecureFromFixture() throws {
        let uri = loadFixture("hy2-insecure")
        XCTAssertFalse(uri.isEmpty, "Fixture hy2-insecure.txt должна быть непустой")
        let parsed = try Hysteria2URIParser.parse(uri)
        XCTAssertTrue(parsed.allowInsecure, "hy2-insecure fixture → allowInsecure=true (D-08)")
        XCTAssertEqual(parsed.host, "selfsigned.test")
        XCTAssertEqual(parsed.port, 443)
    }

    // MARK: D-09 — multi-port (443,8443) throws multiPortNotSupported

    func test_multiPort_rejects() throws {
        let uri = loadFixture("hy2-multi-port")
        XCTAssertFalse(uri.isEmpty, "Fixture hy2-multi-port.txt должна быть непустой")
        XCTAssertThrowsError(try Hysteria2URIParser.parse(uri)) { err in
            guard let e = err as? Hysteria2URIError else {
                XCTFail("Expected Hysteria2URIError, got \(err)"); return
            }
            if case .multiPortNotSupported = e {
                // ok
            } else {
                XCTFail("Expected .multiPortNotSupported, got \(e)")
            }
        }
    }

    // MARK: D-09 — multi-port (с тире) — тоже throws

    func test_multiPort_dashRange_rejects() throws {
        let uri = "hy2://auth@host.example:443-8443?sni=host.example"
        XCTAssertThrowsError(try Hysteria2URIParser.parse(uri)) { err in
            guard let e = err as? Hysteria2URIError else {
                XCTFail("Expected Hysteria2URIError, got \(err)"); return
            }
            if case .multiPortNotSupported(let p) = e {
                XCTAssertTrue(p.contains("-"), "portPart should preserve `-` for dash-range form")
            } else {
                XCTFail("Expected .multiPortNotSupported, got \(e)")
            }
        }
    }

    // MARK: PROTO-05 — obfs=salamander valid

    func test_obfsSalamander_parses() throws {
        let uri = loadFixture("hy2-with-obfs")
        XCTAssertFalse(uri.isEmpty, "Fixture hy2-with-obfs.txt должна быть непустой")
        let parsed = try Hysteria2URIParser.parse(uri)
        XCTAssertEqual(parsed.obfs, "salamander")
        XCTAssertNotNil(parsed.obfsPassword)
        XCTAssertFalse(parsed.obfsPassword?.isEmpty ?? true, "obfs-password should be non-empty")
    }

    // MARK: PROTO-05 — obfs не salamander → throws unsupportedObfs

    func test_obfsNotSalamander_throws() throws {
        let uri = "hy2://auth@host.example:443?sni=host.example&obfs=plain&obfs-password=xyz"
        XCTAssertThrowsError(try Hysteria2URIParser.parse(uri)) { err in
            guard let e = err as? Hysteria2URIError else {
                XCTFail("Expected Hysteria2URIError, got \(err)"); return
            }
            if case .unsupportedObfs(let o) = e {
                XCTAssertEqual(o, "plain")
            } else {
                XCTFail("Expected .unsupportedObfs(\"plain\"), got \(e)")
            }
        }
    }

    // MARK: D-09 default port (443)

    func test_defaultPort() throws {
        let uri = "hy2://auth@host.example?sni=host.example"
        let parsed = try Hysteria2URIParser.parse(uri)
        XCTAssertEqual(parsed.port, 443, "URI без явного port → default 443")
    }

    // MARK: Malformed URI (без `@`) throws malformedURI

    func test_malformedURI_throws() throws {
        let uri = "hy2://noauthhost.example:443"  // no '@' → no user → malformedURI
        XCTAssertThrowsError(try Hysteria2URIParser.parse(uri)) { err in
            XCTAssertEqual(err as? Hysteria2URIError, .malformedURI)
        }
    }

    // MARK: SNI fallback chain — отсутствие sni= → fallback на host

    func test_sniFallback_toHost() throws {
        let uri = "hy2://auth@host.example:443"
        let parsed = try Hysteria2URIParser.parse(uri)
        XCTAssertEqual(parsed.sni, "host.example", "sni absent → fallback to host")
    }

    // MARK: fingerprint pickup из `fp=` (Hysteria2 синоним fingerprint)

    func test_fingerprintFromFP() throws {
        let uri = "hy2://auth@host.example:443?sni=host.example&fp=firefox"
        let parsed = try Hysteria2URIParser.parse(uri)
        XCTAssertEqual(parsed.fingerprint, "firefox")
    }

    // MARK: pinSHA256 pickup

    func test_pinSHA256_extracted() throws {
        let uri = "hy2://auth@host.example:443?sni=host.example&pinSHA256=abcd1234efgh5678"
        let parsed = try Hysteria2URIParser.parse(uri)
        XCTAssertEqual(parsed.pinSHA256, "abcd1234efgh5678")
    }
}
