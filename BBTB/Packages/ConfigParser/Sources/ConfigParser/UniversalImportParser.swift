import Foundation

/// IMP-04 — результат полного import flow.
public struct ImportResult: Sendable {
    public let supported: [ImportedServer]
    public let unsupported: [ImportedServer]
    public let failed: [ImportedServer]  // .invalid cases
    public let subscriptionURL: String?
    public let source: ImportSource
    public let metadata: SubscriptionMetadata?

    public init(supported: [ImportedServer], unsupported: [ImportedServer],
                failed: [ImportedServer], subscriptionURL: String?,
                source: ImportSource, metadata: SubscriptionMetadata?) {
        self.supported = supported; self.unsupported = unsupported; self.failed = failed
        self.subscriptionURL = subscriptionURL; self.source = source; self.metadata = metadata
    }
}

public enum UniversalImportError: Error, LocalizedError, Equatable {
    case empty
    case unknownInputFormat(snippet: String)
    case fetchFailed(String)
    case v2rayJSONUnsupported
    case noValidEntries

    public var errorDescription: String? {
        switch self {
        case .empty: return "Input is empty"
        case .unknownInputFormat(let s): return "Unknown input format: \(s)"
        case .fetchFailed(let s): return "Fetch failed: \(s)"
        case .v2rayJSONUnsupported: return "V2Ray JSON format not supported (use sing-box format)"
        case .noValidEntries: return "No valid entries found"
        }
    }
}

/// Phase 3 — protocol-обёртка над парсером, позволяющая внедрить test-double в
/// `ConfigImporter` без необходимости звать сеть / создавать реальный `UniversalImportParser`.
/// Real impl — `UniversalImportParser` (actor), conformance ниже.
public protocol UniversalImportParsing: Sendable {
    func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult
}

/// D-02 / RESEARCH §6 — universal entry point для любого формата раздачи ссылок.
///
/// Classifies raw input (single URI / multi-line / HTTPS URL / JSON / base64) and
/// dispatches to specialized parsers/fetchers. Per-URI failures don't abort the
/// whole import (RESEARCH §6.4) — instead routed to `failed`/`unsupported` arrays.
public actor UniversalImportParser: UniversalImportParsing {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func `import`(rawInput: String, source: ImportSource = .pasteboard) async throws -> ImportResult {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UniversalImportError.empty }

        let classification = classify(trimmed)
        switch classification {
        case .subscriptionURL(let url):
            return try await fetchAndParseSubscription(url: url)
        case .singBoxJSON(let body):
            return try parseSingBoxJSON(body, source: source, subscriptionURL: nil, metadata: nil)
        case .v2rayJSON:
            throw UniversalImportError.v2rayJSONUnsupported
        case .singleURI(let uri):
            return parseSingleURI(uri, source: source, subscriptionURL: nil)
        case .multilineURIList(let lines):
            return parseMultiline(lines, source: source == .pasteboard ? .multilineText : source,
                                  subscriptionURL: nil, metadata: nil)
        case .base64URIList(let decoded):
            let lines = decoded.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            return parseMultiline(lines, source: source, subscriptionURL: nil, metadata: nil)
        case .clashYAML(let body):
            return parseClashYAML(body, source: source, subscriptionURL: nil)
        case .unknown(let snippet):
            throw UniversalImportError.unknownInputFormat(snippet: snippet)
        }
    }

    enum InputClass {
        case singleURI(String)
        case multilineURIList([String])
        case subscriptionURL(URL)
        case singBoxJSON(String)
        case v2rayJSON(reason: String)
        case base64URIList(String)
        case clashYAML(String)
        case unknown(snippet: String)
    }

    func classify(_ trimmed: String) -> InputClass {
        // 1. HTTPS URL?
        if (trimmed.hasPrefix("https://") || trimmed.hasPrefix("HTTPS://")),
           let url = URL(string: trimmed),
           !trimmed.contains("\n") {
            return .subscriptionURL(url)
        }
        // 2. JSON?
        if trimmed.hasPrefix("{") {
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outbounds = json["outbounds"] as? [[String: Any]] {
                let hasSingBoxType = outbounds.contains { $0["type"] != nil }
                let hasV2RayProtocol = outbounds.contains { $0["protocol"] != nil && $0["type"] == nil }
                if hasV2RayProtocol && !hasSingBoxType {
                    return .v2rayJSON(reason: "outbounds use `protocol` field")
                }
                return .singBoxJSON(trimmed)
            }
            return .unknown(snippet: String(trimmed.prefix(80)))
        }
        // 2.5. Clash YAML? (D-13 — детектирование per planning context).
        // Маркеры: starts with `proxies:` OR contains `\nproxies:` OR contains `mixed-port:`
        // OR contains `allow-lan:` (Clash YAML top-level keys). Lowercased сравнение для
        // tolerance к `Proxies:` варианту. Проверка ДО URI prefix check — Clash YAML body
        // не должен спутаться с base64 fallback далее.
        let trimmedLower = trimmed.lowercased()
        if trimmedLower.hasPrefix("proxies:")
            || trimmedLower.contains("\nproxies:")
            || trimmedLower.hasPrefix("mixed-port:")
            || trimmedLower.contains("\nmixed-port:")
            || trimmedLower.hasPrefix("allow-lan:")
            || trimmedLower.contains("\nallow-lan:") {
            return .clashYAML(trimmed)
        }
        // 3. URI prefix?
        let lower = trimmed.lowercased()
        let knownPrefix = StubParsers.knownSchemes.first { lower.hasPrefix("\($0)://") }
        if knownPrefix != nil {
            // multi-line vs single
            let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init).filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            if lines.count > 1 {
                return .multilineURIList(lines)
            }
            return .singleURI(trimmed)
        }
        // 4. Multi-line check (might be mix of URI + garbage, like Test 6).
        let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if lines.count > 1 {
            // Check if any line starts with known URI scheme.
            let hasAnyURI = lines.contains { line in
                let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
                return StubParsers.knownSchemes.contains { lowered.hasPrefix("\($0)://") }
            }
            if hasAnyURI {
                return .multilineURIList(lines)
            }
        }
        // 5. Base64 attempt.
        if let decoded = SubscriptionURLFetcher.decodeBase64(trimmed),
           isPrintableURIList(decoded) {
            return .base64URIList(decoded)
        }
        return .unknown(snippet: String(trimmed.prefix(80)))
    }

    private func isPrintableURIList(_ s: String) -> Bool {
        let lines = s.split(whereSeparator: \.isNewline).map(String.init)
        return lines.contains { line in
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            return StubParsers.knownSchemes.contains { lowered.hasPrefix("\($0)://") }
        }
    }

    private func parseSingleURI(_ uri: String, source: ImportSource, subscriptionURL: String?) -> ImportResult {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = trimmed.split(separator: ":").first.map { String($0).lowercased() } ?? ""

        switch scheme {
        case "vless":
            do {
                // Phase 4 D-02 — VLESSURIParser.parse возвращает AnyParsedConfig напрямую
                // (двойная ветка vlessReality / vlessTLS). НЕ оборачиваем в .vlessReality.
                let parsedConfig = try VLESSURIParser.parse(trimmed)
                let name = vlessName(from: parsedConfig)
                return ImportResult(
                    supported: [.supported(name: name, parsed: parsedConfig, rawURI: trimmed)],
                    unsupported: [], failed: [],
                    subscriptionURL: subscriptionURL, source: source, metadata: nil
                )
            } catch {
                return ImportResult(supported: [], unsupported: [],
                                    failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)],
                                    subscriptionURL: subscriptionURL, source: source, metadata: nil)
            }

        case "trojan":
            do {
                let parsed = try TrojanURIParser.parse(trimmed)
                let name = parsed.remarks ?? "\(parsed.host):\(parsed.port)"
                return ImportResult(
                    supported: [.supported(name: name, parsed: .trojan(parsed), rawURI: trimmed)],
                    unsupported: [], failed: [],
                    subscriptionURL: subscriptionURL, source: source, metadata: nil
                )
            } catch {
                return ImportResult(supported: [], unsupported: [],
                                    failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)],
                                    subscriptionURL: subscriptionURL, source: source, metadata: nil)
            }

        case "ss":
            // Phase 4 Plan 03 — PROTO-04 / D-04 / D-05 / D-11.
            // unsupportedMethod (whitelist rejection) → .unsupported (метаданные сохраняются для UI).
            // Любая другая parse-ошибка (malformedURI / missingHost / missingPort / malformedUserinfo) → .failed.invalid.
            do {
                let parsed = try ShadowsocksURIParser.parse(trimmed)
                let name = parsed.remarks ?? "\(parsed.host):\(parsed.port)"
                return ImportResult(
                    supported: [.supported(name: name, parsed: .shadowsocks(parsed), rawURI: trimmed)],
                    unsupported: [], failed: [],
                    subscriptionURL: subscriptionURL, source: source, metadata: nil
                )
            } catch ShadowsocksURIError.unsupportedMethod(let method) {
                _ = method  // capture for clarity; reason carries the semantics.
                // Извлекаем host/port best-effort из URLComponents — они валидны (метод проверяется
                // ПОСЛЕ host/port assertions в parser-е).
                let comps = URLComponents(string: trimmed)
                let host = comps?.host ?? "<unknown>"
                let port = comps?.port ?? 0
                let name = comps?.fragment?.removingPercentEncoding ?? "\(host):\(port)"
                return ImportResult(
                    supported: [],
                    unsupported: [.unsupported(
                        name: name, scheme: "ss", host: host, port: port,
                        rawURI: trimmed, reason: .unsupportedSSMethod
                    )],
                    failed: [],
                    subscriptionURL: subscriptionURL, source: source, metadata: nil
                )
            } catch {
                return ImportResult(supported: [], unsupported: [],
                                    failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)],
                                    subscriptionURL: subscriptionURL, source: source, metadata: nil)
            }

        case "hy2", "hysteria2":
            // Phase 4 Plan 04 — PROTO-05 / D-07 / D-08 / D-09.
            // multiPortNotSupported → .unsupported (метаданные сохраняются для UI: показать
            // пользователю что multi-port формат не поддерживается — Phase 7+).
            // Прочие parse-ошибки (malformedURI / missingAuth / unsupportedObfs) → .failed.invalid.
            do {
                let parsed = try Hysteria2URIParser.parse(trimmed)
                let name = parsed.remarks ?? "\(parsed.host):\(parsed.port)"
                return ImportResult(
                    supported: [.supported(name: name, parsed: .hysteria2(parsed), rawURI: trimmed)],
                    unsupported: [], failed: [],
                    subscriptionURL: subscriptionURL, source: source, metadata: nil
                )
            } catch Hysteria2URIError.multiPortNotSupported(let portSpec) {
                _ = portSpec
                // Извлекаем host best-effort из строки между `@` и `:` (URLComponents
                // вернёт nil для multi-port URI).
                let afterAt = String(trimmed.split(separator: "@", maxSplits: 1).last ?? "")
                let beforeQuery = String(
                    afterAt.split(maxSplits: 1, whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
                        .first ?? Substring("")
                )
                let host = String(beforeQuery.split(separator: ":", maxSplits: 1).first ?? Substring("<unknown>"))
                let displayHost = host.isEmpty ? "<unknown>" : host
                let fragmentName: String? = trimmed.split(separator: "#", maxSplits: 1).count == 2
                    ? String(trimmed.split(separator: "#", maxSplits: 1).last!).removingPercentEncoding
                    : nil
                let name = fragmentName ?? "\(displayHost):multi-port"
                return ImportResult(
                    supported: [],
                    unsupported: [.unsupported(
                        name: name, scheme: scheme, host: displayHost, port: 0,
                        rawURI: trimmed, reason: .multiPortNotSupported
                    )],
                    failed: [],
                    subscriptionURL: subscriptionURL, source: source, metadata: nil
                )
            } catch {
                return ImportResult(supported: [], unsupported: [],
                                    failed: [.invalid(rawURI: trimmed, error: error.localizedDescription)],
                                    subscriptionURL: subscriptionURL, source: source, metadata: nil)
            }

        default:
            if StubParsers.knownSchemes.contains(scheme) {
                // Known but unsupported scheme — stub-parser.
                let stub = StubParsers.parseAsUnsupported(trimmed)
                if case .unsupported = stub {
                    return ImportResult(supported: [], unsupported: [stub], failed: [],
                                        subscriptionURL: subscriptionURL, source: source, metadata: nil)
                } else {
                    return ImportResult(supported: [], unsupported: [], failed: [stub],
                                        subscriptionURL: subscriptionURL, source: source, metadata: nil)
                }
            } else {
                // Unknown scheme — invalid.
                return ImportResult(supported: [], unsupported: [],
                                    failed: [.invalid(rawURI: trimmed, error: "Unknown URI scheme: \(scheme)")],
                                    subscriptionURL: subscriptionURL, source: source, metadata: nil)
            }
        }
    }

    /// IMP-05 / D-12 / D-13 — routing для Clash YAML body.
    /// Yams.load throws → возвращаем `ImportResult` со списком `.failed` (не throws на весь
    /// import; пользователь должен увидеть «Clash YAML invalid» вместо crash'а).
    /// При успешном parse — разделяем на supported / unsupported массивы согласно
    /// `ImportedServer` case (per-proxy verdict уже выставлен в ClashYAMLParser).
    private func parseClashYAML(_ body: String, source: ImportSource,
                                 subscriptionURL: String?) -> ImportResult {
        do {
            let items = try ClashYAMLParser.parse(body)
            var supported: [ImportedServer] = []
            var unsupported: [ImportedServer] = []
            for item in items {
                switch item {
                case .supported: supported.append(item)
                case .unsupported: unsupported.append(item)
                case .invalid: unsupported.append(item)  // ClashYAMLParser не emit'ит .invalid, на всякий случай
                }
            }
            return ImportResult(
                supported: supported, unsupported: unsupported, failed: [],
                subscriptionURL: subscriptionURL, source: source, metadata: nil
            )
        } catch {
            let snippet = String(body.prefix(120))
            return ImportResult(
                supported: [], unsupported: [],
                failed: [.invalid(rawURI: snippet, error: error.localizedDescription)],
                subscriptionURL: subscriptionURL, source: source, metadata: nil
            )
        }
    }

    private func parseMultiline(_ lines: [String], source: ImportSource,
                                 subscriptionURL: String?, metadata: SubscriptionMetadata?) -> ImportResult {
        var sup: [ImportedServer] = []
        var unsup: [ImportedServer] = []
        var failed: [ImportedServer] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let r = parseSingleURI(trimmed, source: source, subscriptionURL: subscriptionURL)
            sup.append(contentsOf: r.supported)
            unsup.append(contentsOf: r.unsupported)
            failed.append(contentsOf: r.failed)
        }
        return ImportResult(supported: sup, unsupported: unsup, failed: failed,
                            subscriptionURL: subscriptionURL, source: source, metadata: metadata)
    }

    private func fetchAndParseSubscription(url: URL) async throws -> ImportResult {
        let fetchResult: SubscriptionFetchResult
        do {
            fetchResult = try await SubscriptionURLFetcher.fetch(url: url, session: session)
        } catch {
            throw UniversalImportError.fetchFailed(error.localizedDescription)
        }

        let format = SubscriptionURLFetcher.detectFormat(body: fetchResult.body)
        let bodyStr = String(data: fetchResult.body, encoding: .utf8) ?? ""

        switch format {
        case .base64URIList:
            guard let decoded = SubscriptionURLFetcher.decodeBase64(bodyStr) else {
                throw UniversalImportError.unknownInputFormat(snippet: String(bodyStr.prefix(80)))
            }
            let lines = decoded.split(whereSeparator: \.isNewline).map(String.init)
            return parseMultiline(lines, source: .subscriptionURL(url),
                                  subscriptionURL: url.absoluteString, metadata: fetchResult.metadata)

        case .plainTextURIList:
            let lines = bodyStr.split(whereSeparator: \.isNewline).map(String.init)
            return parseMultiline(lines, source: .subscriptionURL(url),
                                  subscriptionURL: url.absoluteString, metadata: fetchResult.metadata)

        case .singBoxJSON:
            return try parseSingBoxJSON(bodyStr, source: .subscriptionURL(url),
                                         subscriptionURL: url.absoluteString, metadata: fetchResult.metadata)

        case .v2rayJSON:
            throw UniversalImportError.v2rayJSONUnsupported

        case .unknown(let snippet):
            throw UniversalImportError.unknownInputFormat(snippet: snippet)
        }
    }

    /// Parse sing-box config (operator-pre-built) — extract per-outbound server entries.
    private func parseSingBoxJSON(_ body: String, source: ImportSource,
                                   subscriptionURL: String?, metadata: SubscriptionMetadata?) throws -> ImportResult {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = root["outbounds"] as? [[String: Any]]
        else {
            throw UniversalImportError.unknownInputFormat(snippet: String(body.prefix(80)))
        }

        var sup: [ImportedServer] = []
        var unsup: [ImportedServer] = []
        let failed: [ImportedServer] = []

        for outbound in outbounds {
            guard let type = outbound["type"] as? String else { continue }
            // Skip group/special outbounds.
            if ["direct", "block", "dns", "selector", "urltest", "ssh"].contains(type) {
                continue
            }
            switch type {
            case "vless":
                if let parsed = extractParsedVLESS(from: outbound) {
                    let name = (outbound["tag"] as? String) ?? "\(parsed.host):\(parsed.port)"
                    let raw = (try? JSONSerialization.data(withJSONObject: outbound))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    sup.append(.supported(name: name, parsed: .vlessReality(parsed), rawURI: raw))
                }
            case "trojan":
                if let parsed = extractParsedTrojan(from: outbound) {
                    let name = (outbound["tag"] as? String) ?? "\(parsed.host):\(parsed.port)"
                    let raw = (try? JSONSerialization.data(withJSONObject: outbound))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    sup.append(.supported(name: name, parsed: .trojan(parsed), rawURI: raw))
                }
            default:
                // Unsupported sing-box outbound type.
                let host = (outbound["server"] as? String) ?? "<unknown>"
                let port = (outbound["server_port"] as? Int) ?? 0
                let tag = (outbound["tag"] as? String) ?? "\(type) \(host):\(port)"
                let raw = (try? JSONSerialization.data(withJSONObject: outbound))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                unsup.append(.unsupported(name: tag, scheme: type, host: host, port: port,
                                          rawURI: raw, reason: .schemaUnsupportedInPhase2))
            }
        }
        return ImportResult(supported: sup, unsupported: unsup, failed: failed,
                            subscriptionURL: subscriptionURL, source: source, metadata: metadata)
    }

    /// Phase 4 D-02 — извлечь display name из AnyParsedConfig для `vless://` URI.
    /// vlessReality использует remarks (Phase 1 поведение); vlessTLS — то же поведение.
    private func vlessName(from parsed: AnyParsedConfig) -> String {
        switch parsed {
        case .vlessReality(let v):
            return v.remarks ?? "\(v.host):\(v.port)"
        case .vlessTLS(let v):
            return v.remarks ?? "\(v.host):\(v.port)"
        case .trojan, .shadowsocks, .hysteria2:
            // Не должно происходить — VLESSURIParser.parse возвращает только vlessReality/vlessTLS.
            // Defensive fallback: пустое имя приведёт к displayName fallback в UI.
            return ""
        }
    }

    /// Reconstruct ParsedVLESS from sing-box outbound dict (best-effort).
    private func extractParsedVLESS(from o: [String: Any]) -> ParsedVLESS? {
        guard let host = o["server"] as? String,
              let port = o["server_port"] as? Int,
              let uuidStr = o["uuid"] as? String,
              let uuid = UUID(uuidString: uuidStr)
        else { return nil }
        let flow = (o["flow"] as? String) ?? ""
        let tls = (o["tls"] as? [String: Any]) ?? [:]
        let sni = (tls["server_name"] as? String) ?? host
        let utls = (tls["utls"] as? [String: Any]) ?? [:]
        let fp = (utls["fingerprint"] as? String) ?? "chrome"
        let reality = (tls["reality"] as? [String: Any]) ?? [:]
        let pbk = (reality["public_key"] as? String) ?? ""
        let sid = (reality["short_id"] as? String) ?? ""
        let network = (o["network"] as? String) ?? "tcp"
        return ParsedVLESS(
            uuid: uuid, host: host, port: port, flow: flow,
            security: "reality", sni: sni, publicKey: pbk, shortId: sid,
            fingerprint: fp, networkType: network, remarks: o["tag"] as? String
        )
    }

    /// Reconstruct ParsedTrojan from sing-box outbound dict (best-effort).
    private func extractParsedTrojan(from o: [String: Any]) -> ParsedTrojan? {
        guard let host = o["server"] as? String,
              let port = o["server_port"] as? Int,
              let password = o["password"] as? String, !password.isEmpty
        else { return nil }
        let tls = (o["tls"] as? [String: Any]) ?? [:]
        let sni = (tls["server_name"] as? String) ?? host
        let utls = (tls["utls"] as? [String: Any]) ?? [:]
        let fp = (utls["fingerprint"] as? String) ?? "chrome"
        let alpn = (tls["alpn"] as? [String]) ?? ["h2", "http/1.1"]
        let transport: ParsedTrojan.TransportType
        if let transBlock = o["transport"] as? [String: Any],
           (transBlock["type"] as? String) == "ws" {
            let path = (transBlock["path"] as? String) ?? "/"
            let headers = (transBlock["headers"] as? [String: Any]) ?? [:]
            let wsHost = (headers["Host"] as? String) ?? sni
            transport = .ws(path: path, host: wsHost)
        } else {
            transport = .tcp
        }
        return ParsedTrojan(
            password: password, host: host, port: port,
            security: "tls", sni: sni, fingerprint: fp, alpn: alpn,
            transport: transport, remarks: o["tag"] as? String
        )
    }
}
