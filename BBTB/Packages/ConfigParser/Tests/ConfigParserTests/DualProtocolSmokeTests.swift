import XCTest
import PacketTunnelKit
import VPNCore
@testable import ConfigParser

/// W2.T2 — smoke integration: UniversalImportParser → PoolBuilder → SingBoxConfigLoader.validate.
/// Подтверждает что Wave 1 components wire вместе.
final class DualProtocolSmokeTests: XCTestCase {

    private func extractParsed(from result: ImportResult) -> [AnyParsedConfig] {
        result.supported.compactMap { server -> AnyParsedConfig? in
            if case let .supported(_, parsed, _) = server { return parsed }
            return nil
        }
    }

    // MARK: Test 1 — multi-line VLESS+Trojan → valid pool config

    func test_multiline_vless_trojan_buildsValidPoolConfig() async throws {
        let input = """
        vless://550e8400-e29b-41d4-a716-446655440000@host:443?security=reality&flow=xtls-rprx-vision&sni=example.com&fp=chrome&pbk=abc&sid=ef#VLESS-1
        trojan://pwd@host2:2087?security=tls&type=ws&path=/p&sni=example.com#Trojan-1
        """
        let parser = UniversalImportParser()
        let result = try await parser.import(rawInput: input, source: .pasteboard)

        XCTAssertEqual(result.supported.count, 2)
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)

        let configs = extractParsed(from: result)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
        XCTAssertTrue(json.contains("urltest"))
    }

    // MARK: Test 2 — mixed (VLESS+Trojan+SS) → all supported, pool builds (Phase 4 Plan 03)

    /// Pre-Plan-03 поведение: `ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host3:8388` шло в `.unsupported`
    /// (stub parser). Plan 04-03 включает реальный SS handler: base64-userinfo декодируется в
    /// `aes-256-gcm:password`, метод в whitelist'е → `.supported(.shadowsocks(...))`. Тест
    /// зафиксировал shift: теперь 3 supported + pool integrates SS outbound через
    /// `PoolBuilder.buildShadowsocksOutbound` (Plan 04-03 Task 3).
    func test_multiline_withSupportedSS_buildsValidPool() async throws {
        let input = """
        vless://550e8400-e29b-41d4-a716-446655440000@host:443?security=reality&flow=xtls-rprx-vision&sni=example.com&pbk=a&sid=b#VLESS
        trojan://pwd@host2:2087?security=tls&type=ws&path=/p&sni=example.com#Trojan
        ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host3:8388#SS
        """
        let parser = UniversalImportParser()
        let result = try await parser.import(rawInput: input)

        XCTAssertEqual(result.supported.count, 3)
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)

        let configs = extractParsed(from: result)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Test 3 — single Trojan → degenerate config

    func test_singleTrojan_degenerateConfigPassesValidate() async throws {
        let input = "trojan://pwd@host:443?security=tls#Trojan-Only"
        let parser = UniversalImportParser()
        let result = try await parser.import(rawInput: input)
        XCTAssertEqual(result.supported.count, 1)

        let configs = extractParsed(from: result)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
        // Degenerate — нет urltest
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hasUrltest = outbounds.contains { ($0["type"] as? String) == "urltest" }
        XCTAssertFalse(hasUrltest)
        let route = root["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "trojan-0")
    }

    // MARK: Test 4 — only non-supported entries (malformed SS + vmess) → PoolBuilder throws

    /// Phase 4 Plan 03: `ss://abc@host:8388` теперь parses через `ShadowsocksURIParser` и
    /// падает с `malformedUserinfo` → `.failed` (а не `.unsupported`). `vmess://...` остаётся
    /// stub-unsupported. В итоге supported=0 → `PoolBuilder` throws `.noSupportedServers`.
    func test_onlyNonSupported_poolBuilderThrows() async throws {
        let input = """
        ss://abc@host:8388#SS
        vmess://host2:443#VMess
        """
        let parser = UniversalImportParser()
        let result = try await parser.import(rawInput: input)
        XCTAssertEqual(result.supported.count, 0)
        // SS malformed → failed (1); VMess stub → unsupported (1).
        XCTAssertEqual(result.unsupported.count, 1)
        XCTAssertEqual(result.failed.count, 1)

        let configs = extractParsed(from: result)
        XCTAssertThrowsError(try PoolBuilder.buildSingBoxJSON(from: configs)) { err in
            XCTAssertEqual(err as? PoolBuilder.PoolError, .noSupportedServers)
        }
    }
}
