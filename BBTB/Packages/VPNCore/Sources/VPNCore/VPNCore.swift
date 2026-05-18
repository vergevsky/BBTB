// VPNCore — entry-point типы.
//
// **Plan 09 LOW-batch-2 (CodeRabbit PR #23 review fix):** `VPNCore.version`
// was stale ("0.1.0" против project v0.13) и unused в production. Initially
// removed, но CodeRabbit caught source-breaking API change concern. Restored
// as deprecated shim per Swift API-compatibility discipline — gives external
// consumers (if any) a release window для migration.
//
// Marketing version sourced from Info.plist CFBundleShortVersionString.
// Audit theme: «stale TODO comments / version strings».
public enum VPNCore {
    @available(*, deprecated, message: "VPNCore.version is dead — use Bundle.main.object(forInfoDictionaryKey: \"CFBundleShortVersionString\") for marketing version. Will be removed в v1.1+.")
    public static let version = "0.1.0"
}
