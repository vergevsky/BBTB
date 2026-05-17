import XCTest
@testable import PacketTunnelKit

final class SingBoxConfigLoaderTests: XCTestCase {

    // MARK: Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).json")
            throw SingBoxConfigError.malformedJSON
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Valid

    func test_acceptsValidVLESSRealityConfig() throws {
        let json = try loadFixture("valid-vless-reality")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_templateLoadsAndValidates_afterPlaceholderReplacement() throws {
        // R1 self-check: bundled template (с ${...} placeholder'ами) после простой подстановки
        // на непустые строки должен пройти validate. Это гарантирует что Wave 4 при импорте vless://
        // получит на выходе R1-compliant конфиг.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${VLESS_FLOW}", with: "xtls-rprx-vision")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
    }

    // MARK: R1 — forbidden inbounds (SEC-01)

    func test_rejectsSocksInbound() throws {
        let json = try loadFixture("invalid-socks-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("socks"))
        }
    }

    func test_rejectsMixedInbound() throws {
        let json = try loadFixture("invalid-mixed-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("mixed"))
        }
    }

    // MARK: R1 white-list (W3.1) — tun/direct allowed; everything else rejected (default-deny)

    func test_allowsTunInbound() throws {
        let json = try loadFixture("valid-tun-inbound")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_allowsDirectInbound() throws {
        let json = """
        {"inbounds":[{"type":"direct","tag":"d"}],"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_rejectsUnknownInboundType_defaultDeny() throws {
        // Hypothetical future sing-box inbound type that we never reviewed.
        // White-list R1 must reject it without changes to the validator.
        let json = """
        {"inbounds":[{"type":"hypothetical-future-listen-on-localhost","tag":"x"}],"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(
                err as? SingBoxConfigError,
                .forbiddenInboundType("hypothetical-future-listen-on-localhost")
            )
        }
    }

    func test_rejectsInboundWithoutType() throws {
        // Defensive: inbound entry without a "type" key — should still default-deny.
        let json = """
        {"inbounds":[{"tag":"no-type-here"}],"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("<unknown>"))
        }
    }

    func test_rejectsHttpInbound() throws {
        let json = try loadFixture("invalid-http-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("http"))
        }
    }

    // MARK: R1 — experimental APIs (SEC-02)

    func test_rejectsClashAPI() throws {
        let json = try loadFixture("invalid-clash-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("clash_api"))
        }
    }

    func test_rejectsV2RayAPI() throws {
        let json = try loadFixture("invalid-v2ray-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("v2ray_api"))
        }
    }

    func test_rejectsCacheFile() throws {
        let json = try loadFixture("invalid-cache-file")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("cache_file"))
        }
    }

    // MARK: SEC-06 — structure validation

    func test_malformedJSON() throws {
        let json = try loadFixture("malformed")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .malformedJSON)
        }
    }

    func test_noProxyOutbound() throws {
        let json = try loadFixture("no-vless-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noProxyOutbound)
        }
    }

    // MARK: Phase 2 W0.T4 — relaxed validator (RESEARCH §7)

    func test_acceptsTrojanOnlyConfig() throws {
        let json = try loadFixture("valid-trojan-only")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_acceptsPoolWithVlessTrojanUrltest() throws {
        let json = try loadFixture("valid-pool-vless-trojan")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_rejectsConfigWithoutProxyOutbound() throws {
        let json = try loadFixture("invalid-no-proxy-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noProxyOutbound)
        }
    }

    func test_rejectsUrltestWithUnresolvedOutboundRef() throws {
        let json = try loadFixture("invalid-urltest-unresolved-ref")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case let .unresolvedOutboundRef(ref, group) = (err as? SingBoxConfigError) else {
                XCTFail("Expected .unresolvedOutboundRef, got \(err)")
                return
            }
            XCTAssertEqual(ref, "nonexistent-tag")
            XCTAssertEqual(group, "urltest")
        }
    }

    /// T-C6' (closes C1'-001 + A1'-006): route.rules[].outbound references must
    /// resolve to a declared outbound tag (защита от tag-typo leak через proxy).
    func test_rejectsRouteRuleWithUnresolvedOutboundRef() throws {
        let json = """
        {
          "outbounds": [
            { "type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u" },
            { "type": "direct", "tag": "direct" }
          ],
          "route": {
            "rules": [
              { "domain_suffix": [".local"], "outbound": "nonexistent-direct" }
            ],
            "final": "vless-out"
          },
          "experimental": {}
        }
        """
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case let .unresolvedOutboundRef(ref, group) = (err as? SingBoxConfigError) else {
                XCTFail("Expected .unresolvedOutboundRef, got \(err)")
                return
            }
            XCTAssertEqual(ref, "nonexistent-direct")
            XCTAssertEqual(group, "route.rules")
        }
    }

    /// T-C6' (closes C1'-001 + A1'-006): route.final reference must resolve.
    func test_rejectsRouteFinalWithUnresolvedOutboundRef() throws {
        let json = """
        {
          "outbounds": [
            { "type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u" }
          ],
          "route": { "final": "nonexistent-tag" },
          "experimental": {}
        }
        """
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case let .unresolvedOutboundRef(ref, group) = (err as? SingBoxConfigError) else {
                XCTFail("Expected .unresolvedOutboundRef, got \(err)")
                return
            }
            XCTAssertEqual(ref, "nonexistent-tag")
            XCTAssertEqual(group, "route.final")
        }
    }

    /// T-C6' (closes C1'-001 + A1'-006): "dns-out" в route.rules.outbound — legacy
    /// sing-box 1.13 deprecation; expand переписывает в `action: "hijack-dns"`,
    /// потому validate должен это пропускать (даже если operator не задекларировал
    /// `{type:"dns",tag:"dns-out"}` outbound).
    func test_validateAllowsDnsOutLegacyRouteRuleRef() throws {
        let json = """
        {
          "outbounds": [
            { "type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u" }
          ],
          "route": {
            "rules": [
              { "protocol": "dns", "outbound": "dns-out" }
            ],
            "final": "vless-out"
          },
          "experimental": {}
        }
        """
        // Не должен throw — `dns-out` whitelisted в reservedOutboundRefs.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: T-C-H1' route.rule_set[] policy (closes CV-H1)

    /// Helper to build a minimum valid config + arbitrary route block.
    private func makeConfigWithRouteRuleSet(_ ruleSetJSON: String) -> String {
        return """
        {
          "outbounds": [
            { "type": "vless", "tag": "v", "server": "x", "server_port": 443, "uuid": "u" },
            { "type": "direct", "tag": "direct" }
          ],
          "route": {
            "rule_set": \(ruleSetJSON),
            "final": "v"
          },
          "experimental": {}
        }
        """
    }

    /// T-C-H1': reject `type: "remote"` rule_set — bypasses signed-fetch path.
    func test_rejectsRouteRuleSetRemoteType() throws {
        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "evil", "type": "remote", "url": "https://attacker.example.com/rules.srs", "format": "binary" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case let .forbiddenRuleSetType(t) = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetType, got \(err)")
                return
            }
            XCTAssertEqual(t, "remote")
        }
    }

    /// T-C-H1': reject local path outside `rulesCacheDirectory`.
    func test_rejectsRouteRuleSetPathOutsideAllowedDirectory() throws {
        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "evil", "type": "local", "format": "binary",
               "path": "/private/var/mobile/Containers/Shared/AppGroup/X/Library/Caches/pins/subscription-pins-cached.json" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case .forbiddenRuleSetPath = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetPath, got \(err)")
                return
            }
        }
    }

    /// T-C-H1': reject path-traversal markers (defence-in-depth post-canonicalize).
    func test_rejectsRouteRuleSetPathWithTraversal() throws {
        let rulesDir = AppGroupContainer.rulesCacheDirectory.path
        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "evil", "type": "local", "format": "binary",
               "path": "\(rulesDir)/../../../etc/passwd" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case .forbiddenRuleSetPath = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetPath, got \(err)")
                return
            }
        }
    }

    /// T-C-H1': reject basename that does NOT match `^[A-Za-z0-9][A-Za-z0-9._-]+\.srs$`.
    func test_rejectsRouteRuleSetBasenameNotSrs() throws {
        let rulesDir = AppGroupContainer.rulesCacheDirectory.path
        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "evil", "type": "local", "format": "source",
               "path": "\(rulesDir)/.hidden-file" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case .forbiddenRuleSetPath = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetPath, got \(err)")
                return
            }
        }
    }

    /// T-C-H1': accept BBTB's own injected rule_set entries (basename matches regex,
    /// path under rulesCacheDirectory).
    func test_acceptsRouteRuleSetBBTBOwnEntries() throws {
        let rulesDir = AppGroupContainer.rulesCacheDirectory.path
        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "bbtb-block", "type": "local", "format": "binary",
               "path": "\(rulesDir)/bbtb-baseline-block.srs" },
             { "tag": "bbtb-never", "type": "local", "format": "binary",
               "path": "\(rulesDir)/bbtb-baseline-never.srs" }]
        """)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Plan 09 CV-2-H6 — rule_set symlink resolution (closes M-A1-4-01 + C1-4-004)

    /// Plan 09 CV-2-H6: reject path where the final `.srs` file IS a symlink.
    /// Pre-fix: NSString.standardizingPath returned path under rulesDir → validate
    /// passed; libbox followed symlink at open(2) → confused-deputy read.
    /// Post-fix: FileManager.destinationOfSymbolicLink detects symlink, rejects.
    func test_CV_2_H6_rejectsRouteRuleSetSymlinkedFile() throws {
        let fm = FileManager.default
        let rulesDir = AppGroupContainer.rulesCacheDirectory
        let symlinkBasename = "bbtb-cv2h6-symlink-test.srs"
        let symlinkURL = rulesDir.appendingPathComponent(symlinkBasename)
        let targetPath = "/etc/passwd"  // arbitrary outside-sandbox target

        // Cleanup leftover from prior test run.
        try? fm.removeItem(at: symlinkURL)
        defer { try? fm.removeItem(at: symlinkURL) }

        try fm.createSymbolicLink(atPath: symlinkURL.path,
                                  withDestinationPath: targetPath)

        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "evil", "type": "local", "format": "binary",
               "path": "\(symlinkURL.path)" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case .forbiddenRuleSetPath = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetPath, got \(err)")
                return
            }
        }
    }

    /// Plan 09 CV-2-H6: reject DANGLING symlink (symlink whose target doesn't
    /// exist). Per CodeRabbit review on PR #10 + Codex Architect thread
    /// `019e3694`: `FileManager.fileExists(atPath:)` follows symlinks and
    /// returns false for broken links — pre-fix this skipped symlink check
    /// entirely → attacker could create target later → confused-deputy.
    /// Post-fix: `destinationOfSymbolicLink` always called first, rejects.
    func test_CV_2_H6_rejectsBrokenSymlink() throws {
        let fm = FileManager.default
        let rulesDir = AppGroupContainer.rulesCacheDirectory
        let symlinkBasename = "bbtb-cv2h6-broken-symlink-test.srs"
        let symlinkURL = rulesDir.appendingPathComponent(symlinkBasename)
        // Target guaranteed-nonexistent — random UUID under /tmp.
        let nonexistentTarget = "/tmp/bbtb-cv2h6-nonexistent-target-\(UUID().uuidString).srs"

        try? fm.removeItem(at: symlinkURL)
        defer { try? fm.removeItem(at: symlinkURL) }

        try fm.createSymbolicLink(atPath: symlinkURL.path,
                                  withDestinationPath: nonexistentTarget)

        // Sanity: symlink itself exists, but its target does NOT. fileExists
        // follows symlinks → returns false для broken link.
        XCTAssertFalse(fm.fileExists(atPath: symlinkURL.path),
                       "Sanity: fileExists follows symlinks; broken symlink → false")
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: symlinkURL.path),
                        "Sanity: destinationOfSymbolicLink reads link metadata, works even for broken symlinks")

        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "dangling", "type": "local", "format": "binary",
               "path": "\(symlinkURL.path)" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case .forbiddenRuleSetPath = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetPath, got \(err)")
                return
            }
        }
    }

    /// Plan 09 CV-2-H6: accept missing file at validate-time (manifest fetch
    /// writes later). Validation = config-shape; runtime authorization separate.
    func test_CV_2_H6_acceptsRouteRuleSetMissingFile() throws {
        let fm = FileManager.default
        let rulesDir = AppGroupContainer.rulesCacheDirectory
        let missingBasename = "bbtb-cv2h6-missing-test.srs"
        let missingURL = rulesDir.appendingPathComponent(missingBasename)
        try? fm.removeItem(at: missingURL)  // ensure absent
        defer { try? fm.removeItem(at: missingURL) }

        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "future", "type": "local", "format": "binary",
               "path": "\(missingURL.path)" }]
        """)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    /// Plan 09 CV-2-H6: reject when PARENT directory is a symlink pointing
    /// outside rulesDir. Per Codex Code Reviewer thread `019e3684` regression
    /// recommendation. Validator must catch this via parent resolution check
    /// (`parentURL.path != rulesDirURL.path`), not only final-file symlink.
    func test_CV_2_H6_rejectsRouteRuleSetSymlinkedParentDirectory() throws {
        let fm = FileManager.default
        let rulesDir = AppGroupContainer.rulesCacheDirectory
        let linkdirName = "bbtb-cv2h6-linkdir"
        let linkdirURL = rulesDir.appendingPathComponent(linkdirName)
        // Create real target directory outside rulesDir в tmp.
        let outsideTarget = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bbtb-cv2h6-outside-target-\(UUID().uuidString)",
                                    isDirectory: true)
        try fm.createDirectory(at: outsideTarget, withIntermediateDirectories: true)
        try? fm.removeItem(at: linkdirURL)
        defer {
            try? fm.removeItem(at: linkdirURL)
            try? fm.removeItem(at: outsideTarget)
        }
        try fm.createSymbolicLink(atPath: linkdirURL.path,
                                  withDestinationPath: outsideTarget.path)
        let evilFileURL = linkdirURL.appendingPathComponent("evil.srs")

        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "evil-dir", "type": "local", "format": "binary",
               "path": "\(evilFileURL.path)" }]
        """)
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case .forbiddenRuleSetPath = (err as? SingBoxConfigError) else {
                XCTFail("Expected .forbiddenRuleSetPath, got \(err)")
                return
            }
        }
    }

    /// Plan 09 CV-2-H6: accept real (non-symlink) file under rulesDir.
    /// Regression-guard against false positives.
    func test_CV_2_H6_acceptsRouteRuleSetRealFile() throws {
        let fm = FileManager.default
        let rulesDir = AppGroupContainer.rulesCacheDirectory
        let realBasename = "bbtb-cv2h6-real-test.srs"
        let realURL = rulesDir.appendingPathComponent(realBasename)
        try? fm.removeItem(at: realURL)
        defer { try? fm.removeItem(at: realURL) }

        try Data([0x00, 0x01, 0x02]).write(to: realURL, options: .atomic)

        let json = makeConfigWithRouteRuleSet("""
            [{ "tag": "real", "type": "local", "format": "binary",
               "path": "\(realURL.path)" }]
        """)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_missingOutbounds() throws {
        let json = "{\"outbounds\": [], \"route\": { \"final\": \"x\" }, \"experimental\": {}}"
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .missingOutbounds)
        }
    }

    // MARK: expandConfigForTunnel (W3.1)

    private func parse(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    }

    func test_expandConfigForTunnel_addsTunInbound() throws {
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.count, 1)
        XCTAssertEqual(inbounds[0]["type"] as? String, "tun")
        XCTAssertEqual(inbounds[0]["tag"] as? String, "tun-in")
        XCTAssertEqual(inbounds[0]["auto_route"] as? Bool, false)
        XCTAssertEqual(inbounds[0]["stack"] as? String, "gvisor")
        XCTAssertEqual(inbounds[0]["mtu"] as? Int, 1500)
        // Phase 1 (W5 plan B.2): /28 для IPv4.
        // Phase 6 / Wave 2 (D-06): ULA fd00::1/126 для IPv6 blackhole + route_address ["::/0"].
        // Детальные v6 проверки — SingBoxConfigLoaderIPv6Tests.
        XCTAssertEqual(inbounds[0]["address"] as? [String], ["198.18.0.1/28", "fd00::1/126"])
        XCTAssertEqual(inbounds[0]["route_address"] as? [String], ["::/0"])
        // sing-box 1.13 removed `sniff` from inbound — must NOT be present.
        XCTAssertNil(inbounds[0]["sniff"], "sniff field is legacy (removed in sing-box 1.13); use route.rules action:sniff instead")
    }

    func test_expandConfigForTunnel_rewritesLegacyDnsOutbound() throws {
        let json = try loadFixture("legacy-dns-outbound")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)

        // dns outbound удалён
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertFalse(outbounds.contains { ($0["type"] as? String) == "dns" })
        XCTAssertEqual(outbounds.count, 2)

        // route.rules[0] = action:"sniff" (W3.2 injection, см.
        // test_expandConfigForTunnel_injectsSniffAsFirstRule).
        let route = root["route"] as! [String: Any]
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertEqual(rules[0]["action"] as? String, "sniff")
        // Изначальные rules сдвинулись на +1.
        // rules[1]: action=hijack-dns, outbound удалён
        XCTAssertEqual(rules[1]["action"] as? String, "hijack-dns")
        XCTAssertNil(rules[1]["outbound"])
        XCTAssertEqual(rules[1]["protocol"] as? String, "dns")
        // Phase 8 W5: 3 priority rules inserted после hijack-dns (idx 2-4).
        // Legacy rule (domain_suffix → direct) теперь матчится по содержимому, не по index.
        let legacyDirectRule = rules.first {
            ($0["outbound"] as? String) == "direct"
            && ($0["rule_set"] as? String) == nil
        }
        XCTAssertNotNil(legacyDirectRule, "domain_suffix → direct rule должно сохраниться")
        XCTAssertNil(legacyDirectRule?["action"])
    }

    func test_expandConfigForTunnel_isIdempotent() throws {
        let json = try loadFixture("valid-vless-reality")
        let first = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let second = try SingBoxConfigLoader.expandConfigForTunnel(json: first)

        let r1 = try parse(first)
        let r2 = try parse(second)
        let in1 = r1["inbounds"] as! [[String: Any]]
        let in2 = r2["inbounds"] as! [[String: Any]]
        XCTAssertEqual(in1.count, 1)
        XCTAssertEqual(in2.count, 1, "повторный expand не должен дублировать TUN inbound")
        XCTAssertEqual(in1[0]["tag"] as? String, in2[0]["tag"] as? String)
    }

    func test_expandConfigForTunnel_preservesOtherFields() throws {
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)

        // dns block нетронут
        XCTAssertNotNil(root["dns"])
        // outbounds: vless-out + direct остались
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertTrue(outbounds.contains { ($0["type"] as? String) == "vless" })
        XCTAssertTrue(outbounds.contains { ($0["type"] as? String) == "direct" })
        // experimental существует (пустой объект OK)
        XCTAssertNotNil(root["experimental"])
    }

    func test_expandConfigForTunnel_outputPassesValidate_fromLegacyInput() throws {
        // Defense-in-depth: чтобы expand не мог сам добавить что-то запрещённое
        // (регрессия) — на любом валидном входе его output должен проходить validate
        // повторно. Это то самое post-expand re-validation что делает BaseSingBoxTunnel.
        let json = try loadFixture("legacy-dns-outbound")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    func test_expandConfigForTunnel_outputPassesValidate_fromCleanInput() throws {
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    // MARK: expandConfigForTunnel — sniff injection (Phase 1 W3.2 DNS fix)

    func test_expandConfigForTunnel_injectsSniffAsFirstRule() throws {
        // sing-box 1.13: `protocol:dns` matcher не работает без предварительного sniff.
        // Корневая причина device debug 2026-05-11 — DNS UDP падал с "UDP not supported".
        // Sniff coexistence с hijack-dns проверяется в test_rewritesLegacyDnsOutbound.
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let route = root["route"] as! [String: Any]
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertFalse(rules.isEmpty, "route.rules должны существовать после expand")
        XCTAssertEqual(
            rules[0]["action"] as? String, "sniff",
            "sniff action должен быть ПЕРВЫМ правилом — иначе protocol:dns matcher не сработает"
        )
    }

    func test_expandConfigForTunnel_sniffInjectionIsIdempotent() throws {
        let json = try loadFixture("valid-vless-reality")
        let first = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let second = try SingBoxConfigLoader.expandConfigForTunnel(json: first)
        let r2 = try parse(second)
        let rules = (r2["route"] as! [String: Any])["rules"] as! [[String: Any]]
        let sniffCount = rules.filter { ($0["action"] as? String) == "sniff" }.count
        XCTAssertEqual(sniffCount, 1, "повторный expand не должен дублировать sniff action")
    }

    func test_expandConfigForTunnel_sniffAddedEvenWhenNoExistingRules() throws {
        // Конфиг без route.rules вообще — sniff должен появиться.
        let noRulesConfig = """
        {"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: noRulesConfig)
        let root = try parse(expanded)
        let rules = (root["route"] as! [String: Any])["rules"] as! [[String: Any]]
        XCTAssertEqual(rules[0]["action"] as? String, "sniff")
    }

    // MARK: expandConfigForTunnel — log injection (Phase 1 device debug)

    /// Минимальный валидный JSON без log-блока — для изоляции log injection поведения
    /// от того, что несёт fixture `valid-vless-reality.json` (которая ставит log.level=info).
    private let noLogConfig = """
    {"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
    """

    func test_expandConfigForTunnel_omitsLog_whenLogPathNil_andNoExistingLog() throws {
        // Production-сборки вызывают expand без logPath → log секция не добавляется,
        // если её не было во входе.
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: noLogConfig)
        let root = try parse(expanded)
        XCTAssertNil(root["log"], "без logPath и без существующего log-блока — не инжектить")
    }

    func test_expandConfigForTunnel_preservesExistingLog_whenLogPathNil() throws {
        // Существующий log-блок (например, из bundled template) не должен изменяться,
        // если logPath не передан.
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let log = root["log"] as? [String: Any]
        XCTAssertEqual(log?["level"] as? String, "info")
        XCTAssertNil(log?["output"], "без logPath диагностический output не добавляем")
    }

    func test_expandConfigForTunnel_injectsLog_whenLogPathProvided() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: noLogConfig,
            logPath: "/tmp/sing-box.log"
        )
        let root = try parse(expanded)
        let log = root["log"] as? [String: Any]
        XCTAssertNotNil(log)
        XCTAssertEqual(log?["output"] as? String, "/tmp/sing-box.log")
        XCTAssertEqual(log?["level"] as? String, "debug")
        XCTAssertEqual(log?["timestamp"] as? Bool, true)
        XCTAssertEqual(log?["disabled"] as? Bool, false)
    }

    func test_expandConfigForTunnel_logInjectionIsIdempotent() throws {
        let first = try SingBoxConfigLoader.expandConfigForTunnel(json: noLogConfig, logPath: "/tmp/a.log")
        let second = try SingBoxConfigLoader.expandConfigForTunnel(json: first, logPath: "/tmp/a.log")
        let r2 = try parse(second)
        let log = r2["log"] as? [String: Any]
        XCTAssertEqual(log?["output"] as? String, "/tmp/a.log")
        XCTAssertEqual(log?["level"] as? String, "debug")
    }

    func test_expandConfigForTunnel_customLogLevel_propagates() throws {
        // Phase 1 W5 device debug (опция Б): callee может задать кастомный logLevel,
        // например "trace" для Vision flow event diff. Default остаётся "debug".
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: noLogConfig,
            logPath: "/tmp/sing-box.log",
            logLevel: "trace"
        )
        let root = try parse(expanded)
        let log = root["log"] as? [String: Any]
        XCTAssertEqual(log?["level"] as? String, "trace")
        XCTAssertEqual(log?["output"] as? String, "/tmp/sing-box.log")
    }

    func test_expandConfigForTunnel_logOutputPassesValidate() throws {
        // log секция не должна влиять на R1/SEC-06 validate.
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: json,
            logPath: "/tmp/sing-box.log"
        )
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    func test_expandConfigForTunnel_acceptsTemplate_afterPlaceholderReplacement() throws {
        // Sanity: bundled template после фейкового fill — после expand тоже валиден.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${VLESS_FLOW}", with: "xtls-rprx-vision")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: filled)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    // MARK: - Phase 8 W5 (D-01) — rule_set injection tests (RULES-05/06/07 + R10/R1)

    /// Заполняет `${...}` placeholders bundled template'а на валидные значения —
    /// shared helper для всех Phase 8 W5 тестов.
    private func loadFilledTemplate() throws -> String {
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        return template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${VLESS_FLOW}", with: "xtls-rprx-vision")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")
    }

    /// RULES-05/06/07: 3 `route.rule_set` declarations injected с правильными метаданными
    /// (`type:"local"`, `format:"binary"`, path под App Group `Library/Caches/rules/<tag>.srs`).
    func test_expandConfigForTunnel_injectsThreeRuleSetEntries() throws {
        let baseTemplate = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: baseTemplate)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expanded.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])
        let ruleSets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        let tags = ruleSets.compactMap { $0["tag"] as? String }
        XCTAssertEqual(Set(tags), Set(["bbtb-block", "bbtb-never", "bbtb-always"]),
                       "Should inject exactly 3 rule_set declarations")
        for rs in ruleSets {
            XCTAssertEqual(rs["type"] as? String, "local",
                           "rule_set type must be 'local' (sing-box reads from filesystem)")
            XCTAssertEqual(rs["format"] as? String, "binary",
                           "rule_set format must be 'binary' (.srs compiled format)")
            let path = try XCTUnwrap(rs["path"] as? String)
            XCTAssertTrue(path.contains("Library/Caches/rules/"),
                          "Expected App Group rules cache path, got \(path)")
            XCTAssertTrue(path.hasSuffix(".srs"),
                          "rule_set path must end with .srs (compiled rule-set), got \(path)")
        }
    }

    /// RULES-06: priority order block → never → always (sing-box matches first hit
    /// top-down → block доминирует, never override'ит always для same domain).
    func test_expandConfigForTunnel_priorityOrderIsBlockThenNeverThenAlways() throws {
        let template = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expanded.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        // Extract just our 3 rule_set references in their order.
        let phase8 = rules.compactMap { $0["rule_set"] as? String }
        XCTAssertEqual(phase8, ["bbtb-block", "bbtb-never", "bbtb-always"],
                       "Phase 8 priority order must be block > never > always (top-down sing-box matching)")

        // block uses action:reject (drops traffic outright)
        let blockRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-block" })
        XCTAssertEqual(blockRule["action"] as? String, "reject")
        XCTAssertNil(blockRule["outbound"], "block rule must NOT have outbound (action:reject only)")

        // never uses outbound:direct (bypass VPN)
        let neverRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-never" })
        XCTAssertEqual(neverRule["outbound"] as? String, "direct")
        XCTAssertNil(neverRule["action"], "never rule must NOT have action")

        // always uses non-direct proxy outbound (forces through VPN)
        let alwaysRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-always" })
        let alwaysOutbound = try XCTUnwrap(alwaysRule["outbound"] as? String)
        XCTAssertNotEqual(alwaysOutbound, "direct",
                          "always category MUST route через VPN, not direct")
        XCTAssertNotEqual(alwaysOutbound, "block")
    }

    /// RULES-07 / firstProxyTag reuse: `always` outbound matches существующий proxy outbound
    /// tag (urltest/selector/vless/trojan — same set как `route.final` fallback в lines 218-225).
    func test_expandConfigForTunnel_alwaysCategoryUsesValidProxyTag() throws {
        let template = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expanded.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let alwaysRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-always" })
        let alwaysOutbound = try XCTUnwrap(alwaysRule["outbound"] as? String)
        // Resolved firstProxyTag must match один из existing proxy outbound tags.
        let outbounds = try XCTUnwrap(parsed["outbounds"] as? [[String: Any]])
        let proxyTags = outbounds.compactMap { o -> String? in
            guard let type = o["type"] as? String,
                  ["vless", "trojan", "shadowsocks", "vmess", "hysteria2", "wireguard", "tuic",
                   "urltest", "selector"].contains(type) else { return nil }
            return o["tag"] as? String
        }
        XCTAssertTrue(proxyTags.contains(alwaysOutbound),
                      "always outbound '\(alwaysOutbound)' should match один из proxy outbound tags \(proxyTags)")
    }

    /// Idempotency: повторный вызов `expandConfigForTunnel` НЕ дублирует rule_set
    /// declarations или priority rules (existing tag / rule_set ref filter).
    func test_expandConfigForTunnel_rulesetInjectionIsIdempotent() throws {
        let template = try loadFilledTemplate()
        let firstExpand = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let secondExpand = try SingBoxConfigLoader.expandConfigForTunnel(json: firstExpand)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(secondExpand.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])

        let ruleSets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        XCTAssertEqual(ruleSets.count, 3,
                       "rule_set entries deduped — exactly 3 после двух expand'ов, not 6")

        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let bbtbRefs = rules.compactMap { $0["rule_set"] as? String }
        XCTAssertEqual(bbtbRefs.count, 3,
                       "priority rules deduped — exactly 3 после двух expand'ов, not 6")
    }

    /// R10 invariant: post-expand `validate(json:)` MUST pass.
    /// `route.rule_set` declarations и `action:reject` priority rules не пересекаются
    /// ни с одним из R1 / SEC-02 / SEC-06 gates (inbound whitelist, experimental,
    /// proxy outbound presence, urltest reference resolution).
    func test_expandConfigForTunnel_validatePassesAfterRulesetExpansion_R10invariant() throws {
        let template = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded),
                         "R10 invariant: post-expand validate MUST pass — rule_set injection не должно ломать gate")
    }

    /// R1 invariant (Phase 8 extension): template `SingBoxConfigTemplate.vless-reality.json`
    /// должен оставаться bare — никаких inline `rule_set` keys. Single source of truth
    /// для rule_set injection — runtime `expandConfigForTunnel`.
    func test_template_doesNotContainInlineRuleSetBlock_R1invariant() throws {
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        XCTAssertFalse(template.contains("\"rule_set\""),
                       "Template must NOT embed inline rule_set key — runtime expansion is single source")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(template.utf8)) as? [String: Any])
        if let route = parsed["route"] as? [String: Any] {
            XCTAssertNil(route["rule_set"],
                         "Route block в template must NOT contain rule_set key")
        }
    }

    // MARK: - Phase 10 W2 (DPI-05) — Mux injection tests

    /// App Group UserDefaults key for mux toggle (DPI-05).
    private let muxKey = "app.bbtb.muxEnabled"
    /// App Group suite identifier — mirrors AppGroupContainer.identifier.
    private let appGroupSuite = "group.app.bbtb.shared"

    /// Записывает mux toggle в App Group UserDefaults (имитирует Wave 1 SettingsViewModel).
    private func setMuxToggle(_ value: Bool) {
        UserDefaults(suiteName: appGroupSuite)?.set(value, forKey: muxKey)
        UserDefaults(suiteName: appGroupSuite)?.synchronize()
    }

    /// Очищает mux toggle из App Group UserDefaults.
    private func clearMuxToggle() {
        UserDefaults(suiteName: appGroupSuite)?.removeObject(forKey: muxKey)
        UserDefaults(suiteName: appGroupSuite)?.synchronize()
    }

    override func tearDown() {
        super.tearDown()
        clearMuxToggle()
        clearStunBlockToggle()
    }

    /// Строит минимальный валидный sing-box JSON с заданным массивом outbounds.
    /// Структура соответствует R1/SEC-06 требованиям (есть хотя бы один proxy outbound, route, experimental).
    private func makeMinimalSingBoxJSON(outbounds: [[String: Any]]) throws -> String {
        let root: [String: Any] = [
            "inbounds": [[String: Any]](),
            "outbounds": outbounds,
            "route": [
                "final": (outbounds.first?["tag"] as? String) ?? "proxy",
                "rules": [[String: Any]]()
            ] as [String: Any],
            "experimental": [String: Any]()
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        return String(data: data, encoding: .utf8)!
    }

    /// Достаёт первый outbound из результата expandConfigForTunnel, сериализованного обратно.
    private func firstOutbound(inExpanded json: String, withTag tag: String? = nil) throws -> [String: Any] {
        let root = try parse(json)
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        if let tag = tag {
            return try XCTUnwrap(outbounds.first { ($0["tag"] as? String) == tag })
        }
        return try XCTUnwrap(outbounds.first)
    }

    // MARK: test_mux_* — 10 тестов (8 основных + 2 bonus)

    /// Test 1: VLESS plain (без reality, без flow) + muxEnabled=true → multiplex injected.
    func test_mux_injects_for_vless_plain_when_toggle_on() throws {
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "vless",
            "tag": "vless-plain",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any]
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "vless-plain")
        let multiplex = try XCTUnwrap(ob["multiplex"] as? [String: Any],
                                      "VLESS plain с muxEnabled=true должен получить multiplex блок")
        XCTAssertEqual(multiplex["enabled"] as? Bool, true)
        XCTAssertEqual(multiplex["protocol"] as? String, "smux")
        XCTAssertEqual(multiplex["max_connections"] as? Int, 4)
        XCTAssertEqual(multiplex["padding"] as? Bool, true)
    }

    /// Test 2: VLESS+Reality (tls.reality.enabled=true) + muxEnabled=true → NO multiplex (D-09).
    func test_mux_skipped_for_vless_reality() throws {
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "vless",
            "tag": "vless-reality",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "tls": [
                "enabled": true,
                "server_name": "www.microsoft.com",
                "utls": ["enabled": true, "fingerprint": "chrome"] as [String: Any],
                "reality": ["enabled": true, "public_key": "abc123", "short_id": "01234567"] as [String: Any]
            ] as [String: Any]
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "vless-reality")
        XCTAssertNil(ob["multiplex"],
                     "VLESS+Reality НЕ должен получать multiplex (D-09 — Reality incompatible)")
    }

    /// Test 3: VLESS+Vision (flow=xtls-rprx-vision) + muxEnabled=true → NO multiplex (D-09, issue #453).
    func test_mux_skipped_for_vless_vision() throws {
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "vless",
            "tag": "vless-vision",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "flow": "xtls-rprx-vision",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any]
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "vless-vision")
        XCTAssertNil(ob["multiplex"],
                     "VLESS+Vision НЕ должен получать multiplex (D-09 — Vision/XTLS incompatible, SagerNet #453)")
    }

    /// Test 4: Trojan + muxEnabled=true → multiplex injected с правильными значениями.
    func test_mux_injects_for_trojan() throws {
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "trojan",
            "tag": "trojan-out",
            "server": "example.com",
            "server_port": 443,
            "password": "secret",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any]
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "trojan-out")
        let multiplex = try XCTUnwrap(ob["multiplex"] as? [String: Any],
                                      "Trojan с muxEnabled=true должен получить multiplex блок")
        XCTAssertEqual(multiplex["enabled"] as? Bool, true)
        XCTAssertEqual(multiplex["protocol"] as? String, "smux")
        XCTAssertEqual(multiplex["max_connections"] as? Int, 4)
        XCTAssertEqual(multiplex["padding"] as? Bool, true)
    }

    /// Test 5: Shadowsocks-2022 + muxEnabled=true → multiplex injected.
    func test_mux_injects_for_shadowsocks_2022() throws {
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "shadowsocks",
            "tag": "ss-out",
            "server": "example.com",
            "server_port": 8388,
            "method": "2022-blake3-aes-128-gcm",
            "password": "base64secret"
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "ss-out")
        let multiplex = try XCTUnwrap(ob["multiplex"] as? [String: Any],
                                      "Shadowsocks-2022 с muxEnabled=true должен получить multiplex блок")
        XCTAssertEqual(multiplex["enabled"] as? Bool, true)
        XCTAssertEqual(multiplex["protocol"] as? String, "smux")
        XCTAssertEqual(multiplex["max_connections"] as? Int, 4)
        XCTAssertEqual(multiplex["padding"] as? Bool, true)
    }

    /// Test 6: TUIC и Hysteria2 + muxEnabled=true → НИ ОДИН не получает multiplex (D-09).
    func test_mux_skipped_for_tuic_and_hysteria2() throws {
        setMuxToggle(true)
        let tuicOutbound: [String: Any] = [
            "type": "tuic",
            "tag": "tuic-out",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "password": "secret"
        ]
        let hy2Outbound: [String: Any] = [
            "type": "hysteria2",
            "tag": "hy2-out",
            "server": "example.com",
            "server_port": 443,
            "password": "secret"
        ]
        // Нужен хотя бы один proxy-outbound типа из proxyOutboundTypes для validate.
        // Добавим trojan как третий совместимый outbound (для SEC-06).
        let trojanOutbound: [String: Any] = [
            "type": "trojan",
            "tag": "trojan-anchor",
            "server": "example.com",
            "server_port": 443,
            "password": "secret"
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [tuicOutbound, hy2Outbound, trojanOutbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        let tuic = try XCTUnwrap(outbounds.first { ($0["tag"] as? String) == "tuic-out" })
        let hy2 = try XCTUnwrap(outbounds.first { ($0["tag"] as? String) == "hy2-out" })
        XCTAssertNil(tuic["multiplex"], "TUIC НЕ должен получать multiplex (QUIC нативно multiplexed, D-09)")
        XCTAssertNil(hy2["multiplex"], "Hysteria2 НЕ должен получать multiplex (QUIC нативно multiplexed, D-09)")
    }

    /// Test 7: muxEnabled=false (или ключ отсутствует) → NO multiplex даже для Trojan.
    func test_mux_skipped_when_toggle_off() throws {
        clearMuxToggle()  // toggle explicitly absent = false
        let outbound: [String: Any] = [
            "type": "trojan",
            "tag": "trojan-out",
            "server": "example.com",
            "server_port": 443,
            "password": "secret"
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "trojan-out")
        XCTAssertNil(ob["multiplex"],
                     "muxEnabled=false/absent → NO multiplex (global toggle controls injection)")
    }

    /// Test 8: Idempotency — повторный expand на VLESS plain не дублирует multiplex.
    func test_mux_idempotent() throws {
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "vless",
            "tag": "vless-plain",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any]
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let firstExpanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let secondExpanded = try SingBoxConfigLoader.expandConfigForTunnel(json: firstExpanded)
        let ob = try firstOutbound(inExpanded: secondExpanded, withTag: "vless-plain")
        let multiplex = try XCTUnwrap(ob["multiplex"] as? [String: Any],
                                      "multiplex должен присутствовать после двух expand'ов")
        // Проверяем что multiplex не стал вложенным или дублированным.
        XCTAssertEqual(multiplex["enabled"] as? Bool, true)
        XCTAssertEqual(multiplex["protocol"] as? String, "smux")
        XCTAssertEqual(multiplex["max_connections"] as? Int, 4)
        // multiplex ключ должен быть flat-dict, не содержать вложенный "multiplex" ключ.
        XCTAssertNil(multiplex["multiplex"], "idempotent: multiplex не должен быть вложен внутрь себя")
    }

    /// Test 9 (bonus): Per-server override — существующий multiplex (yamux) сохраняется, даже если global OFF.
    /// D-08 «двойной контроль» — per-server URI override уважается даже при global toggle off.
    func test_mux_preserves_existing_per_server_override() throws {
        clearMuxToggle()  // global toggle OFF
        let existingMultiplex: [String: Any] = [
            "enabled": true,
            "protocol": "yamux",
            "max_connections": 8,
            "padding": false
        ]
        let outbound: [String: Any] = [
            "type": "vless",
            "tag": "vless-mux-override",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any],
            "multiplex": existingMultiplex
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "vless-mux-override")
        let multiplex = try XCTUnwrap(ob["multiplex"] as? [String: Any],
                                      "Per-server multiplex override должен сохраниться при global OFF")
        // D-08: существующий yamux per-server не перезаписывается глобальным smux.
        XCTAssertEqual(multiplex["protocol"] as? String, "yamux",
                       "D-08: per-server yamux не должен перезаписываться global smux даже при toggle ON")
        XCTAssertEqual(multiplex["max_connections"] as? Int, 8)
    }

    // MARK: - Phase 10 W3 (BIO-04) — STUN block route.rule injection tests

    /// App Group UserDefaults key for STUN block toggle (BIO-04).
    private let stunBlockKey = "app.bbtb.stunBlockEnabled"

    /// Записывает STUN block toggle в App Group UserDefaults.
    private func setStunBlockToggle(_ value: Bool) {
        UserDefaults(suiteName: appGroupSuite)?.set(value, forKey: stunBlockKey)
        UserDefaults(suiteName: appGroupSuite)?.synchronize()
    }

    /// Очищает STUN block toggle из App Group UserDefaults.
    private func clearStunBlockToggle() {
        UserDefaults(suiteName: appGroupSuite)?.removeObject(forKey: stunBlockKey)
        UserDefaults(suiteName: appGroupSuite)?.synchronize()
    }

    /// T-B9 / A1-001: STUN block rule fingerprint helper (replaces `tag == "bbtb-stun-block"` —
    /// sing-box 1.13 schema strips `tag` field on rules).
    private func isStunBlockRule(_ rule: [String: Any]) -> Bool {
        guard
            (rule["action"] as? String) == "reject",
            (rule["network"] as? String) == "udp",
            (rule["port"] as? [Int]) == [3478, 5349]
        else { return false }
        return true
    }

    /// Test 1: stunBlockEnabled=true → route.rules содержит entry с tag="bbtb-stun-block",
    /// порт=[3478,5349], network=udp, action=reject, method=drop. Entry находится ПОСЛЕ hijack-dns.
    func test_stun_block_rule_inserted_when_enabled() throws {
        setStunBlockToggle(true)
        let json = try makeMinimalSingBoxJSON(outbounds: [
            ["type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u"]
        ])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let stunRule = try XCTUnwrap(rules.first { isStunBlockRule($0) },
                                     "STUN block rule должен присутствовать в route.rules при stunBlockEnabled=true")
        XCTAssertEqual(stunRule["action"] as? String, "reject")
        XCTAssertEqual(stunRule["network"] as? String, "udp")
        XCTAssertEqual(stunRule["method"] as? String, "drop")
        // Verify position: STUN block должен идти ПОСЛЕ hijack-dns
        let hijackIdx = rules.firstIndex { ($0["action"] as? String) == "hijack-dns" } ?? -1
        let stunIdx = rules.firstIndex { isStunBlockRule($0) } ?? -1
        XCTAssertGreaterThan(stunIdx, hijackIdx,
                             "STUN block rule должен быть ПОСЛЕ hijack-dns (DNS должен работать)")
    }

    /// Test 2: stunBlockEnabled=false (ключ отсутствует) → НИ ОДНО правило не содержит bbtb-stun-block.
    func test_stun_block_rule_absent_when_disabled() throws {
        clearStunBlockToggle()  // toggle explicitly absent = false
        let json = try makeMinimalSingBoxJSON(outbounds: [
            ["type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u"]
        ])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = (route["rules"] as? [[String: Any]]) ?? []
        let hasStunRule = rules.contains { isStunBlockRule($0) }
        XCTAssertFalse(hasStunRule, "При stunBlockEnabled=false/absent НЕ должно быть bbtb-stun-block rule")
    }

    /// Test 3: stunBlockEnabled=true, двойной expand → ровно ОДНО правило с tag="bbtb-stun-block".
    func test_stun_block_idempotent() throws {
        setStunBlockToggle(true)
        let json = try makeMinimalSingBoxJSON(outbounds: [
            ["type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u"]
        ])
        let firstExpanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let secondExpanded = try SingBoxConfigLoader.expandConfigForTunnel(json: firstExpanded)
        let root = try parse(secondExpanded)
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = (route["rules"] as? [[String: Any]]) ?? []
        let stunCount = rules.filter { isStunBlockRule($0) }.count
        XCTAssertEqual(stunCount, 1, "Idempotent: ровно ОДНО bbtb-stun-block rule после двух expand'ов")
    }

    /// Test 4: stunBlockEnabled=true → проверка полного содержимого STUN block правила.
    func test_stun_block_shape() throws {
        setStunBlockToggle(true)
        let json = try makeMinimalSingBoxJSON(outbounds: [
            ["type": "vless", "tag": "vless-out", "server": "x", "server_port": 443, "uuid": "u"]
        ])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let stunRule = try XCTUnwrap(rules.first { isStunBlockRule($0) })
        // T-B9 / A1-001: `tag` field больше не set — sing-box 1.13 route.rules schema
        // strips its. Fingerprint check is via port+network+action.
        XCTAssertNil(stunRule["tag"], "tag field больше не set (sing-box schema не preserves)")
        XCTAssertEqual(stunRule["action"] as? String, "reject")
        XCTAssertEqual(stunRule["network"] as? String, "udp")
        XCTAssertEqual(stunRule["method"] as? String, "drop")
        // port должен быть Array Int [3478, 5349] в этом порядке
        let ports = try XCTUnwrap(stunRule["port"] as? [Int],
                                  "port должен быть Array<Int>, не строка")
        XCTAssertEqual(ports, [3478, 5349], "port должен быть [3478, 5349] в этом порядке")
    }

    /// Test 5: stunBlockEnabled=true И muxEnabled=true → оба inject'а совместимы.
    /// STUN block присутствует; outbounds[0].multiplex присутствует.
    func test_stun_block_coexists_with_mux() throws {
        setStunBlockToggle(true)
        setMuxToggle(true)
        let outbound: [String: Any] = [
            "type": "trojan",
            "tag": "trojan-out",
            "server": "example.com",
            "server_port": 443,
            "password": "secret",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any]
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        // STUN block rule присутствует
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let hasStun = rules.contains { isStunBlockRule($0) }
        XCTAssertTrue(hasStun, "STUN block должен присутствовать при stunBlockEnabled=true")
        // Mux inject'а — multiplex в trojan outbound
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        let trojan = try XCTUnwrap(outbounds.first { ($0["tag"] as? String) == "trojan-out" })
        XCTAssertNotNil(trojan["multiplex"], "Trojan должен получить multiplex при muxEnabled=true")
    }

    /// Test 6 (bonus): stunBlockEnabled=true + Phase 8 rule_set rules already injected →
    /// Phase 8 rules сохранены без изменений по order'у.
    func test_stun_block_preserves_phase8_rule_set_priority() throws {
        setStunBlockToggle(true)
        let template = try loadFilledTemplate()
        // loadFilledTemplate — VLESS+Vision fixture, which expands with Phase 8 rules
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let root = try parse(expanded)
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        // STUN block присутствует
        XCTAssertTrue(rules.contains { isStunBlockRule($0) },
                      "STUN block должен присутствовать при stunBlockEnabled=true")
        // Phase 8 rule_set rules сохранены в правильном порядке
        let phase8 = rules.compactMap { $0["rule_set"] as? String }
        XCTAssertEqual(phase8, ["bbtb-block", "bbtb-never", "bbtb-always"],
                       "Phase 8 priority order должен оставаться block > never > always")
    }

    /// Test 10 (bonus): Per-server override + global ON → existing yamux НЕ перезаписывается на smux.
    /// D-08 «двойной контроль» — global toggle не override'ит per-server URI/Clash setting.
    func test_mux_preserves_existing_when_global_on() throws {
        setMuxToggle(true)  // global toggle ON
        let existingMultiplex: [String: Any] = [
            "enabled": true,
            "protocol": "yamux",
            "max_connections": 8,
            "padding": false
        ]
        let outbound: [String: Any] = [
            "type": "vless",
            "tag": "vless-yamux",
            "server": "example.com",
            "server_port": 443,
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "tls": ["enabled": true, "server_name": "example.com"] as [String: Any],
            "multiplex": existingMultiplex
        ]
        let json = try makeMinimalSingBoxJSON(outbounds: [outbound])
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let ob = try firstOutbound(inExpanded: expanded, withTag: "vless-yamux")
        let multiplex = try XCTUnwrap(ob["multiplex"] as? [String: Any])
        // D-08: global smux НЕ перезаписывает существующий yamux (idempotent if key exists).
        XCTAssertEqual(multiplex["protocol"] as? String, "yamux",
                       "D-08: global toggle не должен overrid'ить per-server yamux на smux")
        XCTAssertEqual(multiplex["max_connections"] as? Int, 8)
    }
}
