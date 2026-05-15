#!/usr/bin/env bash
# Phase 8 / RULES-05 — compile baseline-rules.json → 3 .srs + sign all.
# Invoked manually by developer when baseline-rules.json changes (Pitfall 6 Option A).
# Output: BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/{bbtb-baseline-*.srs,*.sig,baseline-rules-manifest.json,*.json.sig}
#
# Requirements (per W6 user_setup):
# - sing-box CLI v1.13.x (`brew install sing-box`) — SRS rule-set compile.
# - openssl 3.x (`brew install openssl@3` — macOS LibreSSL не поддерживает `pkeyutl -rawin`).
# - jq для JSON manipulation.
# - BBTB_BASELINE_SIGNING_KEY env var → path to Ed25519 private key (PEM).
#
# Modes:
# 1. **Production signing mode** (BBTB_BASELINE_SIGNING_KEY set):
#    Reads the supplied Ed25519 private key, signs all SRS files + manifest.
#    PublicKey.swift НЕ изменяется — assumed уже содержит matching pubkey.
# 2. **Ephemeral mode** (BBTB_BASELINE_SIGNING_KEY unset):
#    Генерирует ephemeral keypair в $TMPDIR, подписывает baseline ему,
#    AND atomically заменяет `publicKeyBytes` в PublicKey.swift на derived
#    32-байтную public key (DER суффикс). Это позволяет worktree CI / autonomous
#    runs пройти full pipeline без external secret-management.
#    После ephemeral run: `grep -E "0x00, 0x01, 0x02, 0x03" PublicKey.swift` == 0
#    (R12 invariant precondition met).

set -euo pipefail

# REPO_ROOT resolves to BBTB/ — both `Packages/` and `scripts/` are siblings.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="${REPO_ROOT}/Packages/RulesEngine/Sources/RulesEngine/Resources"
BASELINE_JSON="${RESOURCES}/baseline-rules.json"
MANIFEST_OUT="${RESOURCES}/baseline-rules-manifest.json"
MANIFEST_SIG_OUT="${RESOURCES}/baseline-rules-manifest.json.sig"
PUBKEY_SWIFT="${REPO_ROOT}/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift"

# Prefer Homebrew openssl@3 на macOS — system /usr/bin/openssl это LibreSSL,
# который НЕ поддерживает `pkeyutl -rawin` для Ed25519.
OPENSSL_BIN="${OPENSSL_BIN:-}"
if [[ -z "$OPENSSL_BIN" ]]; then
    for cand in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl openssl; do
        if command -v "$cand" >/dev/null 2>&1; then
            ver=$("$cand" version 2>/dev/null | awk '{print $1, $2}')
            if [[ "$ver" == OpenSSL\ 3.* ]] || [[ "$ver" == OpenSSL\ 4.* ]]; then
                OPENSSL_BIN="$cand"
                break
            fi
        fi
    done
fi

# Pre-flight checks
command -v sing-box >/dev/null 2>&1 || { echo "ERROR: sing-box CLI not found. Install: brew install sing-box"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found. Install: brew install jq"; exit 1; }
if [[ -z "$OPENSSL_BIN" ]]; then
    echo "ERROR: OpenSSL 3.x not found (system openssl is LibreSSL — no -rawin support)."
    echo "       Install: brew install openssl@3"
    echo "       Or:      export OPENSSL_BIN=/path/to/openssl3"
    exit 1
fi

# Sanity: openssl actually supports -rawin Ed25519 sign on a real file.
SANITY_DIR=$(mktemp -d)
trap 'rm -rf "$SANITY_DIR"' EXIT
"$OPENSSL_BIN" genpkey -algorithm ed25519 -out "$SANITY_DIR/sanity.pem" >/dev/null 2>&1
echo -n "sanity" > "$SANITY_DIR/sanity.msg"
if ! "$OPENSSL_BIN" pkeyutl -sign -rawin -inkey "$SANITY_DIR/sanity.pem" \
        -in "$SANITY_DIR/sanity.msg" -out "$SANITY_DIR/sanity.sig" 2>/dev/null; then
    echo "ERROR: openssl $OPENSSL_BIN does not support -rawin Ed25519 sign."
    echo "       Need OpenSSL 3.x — brew install openssl@3"
    exit 1
fi
SANITY_SIZE=$(wc -c < "$SANITY_DIR/sanity.sig" | tr -d ' ')
if [[ "$SANITY_SIZE" != "64" ]]; then
    echo "ERROR: openssl sanity check produced $SANITY_SIZE-byte signature (expected 64)"
    exit 1
fi

# Resolve signing key + ephemeral mode flag.
EPHEMERAL_MODE=0
EPHEMERAL_DIR=""
if [[ -z "${BBTB_BASELINE_SIGNING_KEY:-}" ]]; then
    EPHEMERAL_MODE=1
    EPHEMERAL_DIR=$(mktemp -d)
    BBTB_BASELINE_SIGNING_KEY="${EPHEMERAL_DIR}/bbtb-ephemeral-rules.pem"
    "$OPENSSL_BIN" genpkey -algorithm ed25519 -out "$BBTB_BASELINE_SIGNING_KEY" >/dev/null 2>&1
    echo "WARNING: BBTB_BASELINE_SIGNING_KEY not set — generated ephemeral keypair."
    echo "         Ephemeral private key: $BBTB_BASELINE_SIGNING_KEY (DELETED on exit)"
    echo "         Will derive matching public key и обновлять PublicKey.swift."
    # Extend cleanup trap to cover ephemeral dir too.
    trap 'rm -rf "$SANITY_DIR" "$EPHEMERAL_DIR"' EXIT
fi

if [[ ! -f "$BBTB_BASELINE_SIGNING_KEY" ]]; then
    echo "ERROR: BBTB_BASELINE_SIGNING_KEY=$BBTB_BASELINE_SIGNING_KEY does not exist"
    exit 1
fi

echo "Baseline source: $BASELINE_JSON"
echo "Resources dir:   $RESOURCES"
echo "Signing key:     $BBTB_BASELINE_SIGNING_KEY"
echo "OpenSSL binary:  $OPENSSL_BIN"
[[ "$EPHEMERAL_MODE" == "1" ]] && echo "Mode:            EPHEMERAL (will update PublicKey.swift)"
[[ "$EPHEMERAL_MODE" == "0" ]] && echo "Mode:            PRODUCTION (PublicKey.swift untouched — assumed pre-populated)"

mkdir -p "$RESOURCES"

# Capture sing-box version для manifest annotation (informational).
SINGBOX_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
echo "sing-box CLI version: $SINGBOX_VERSION"

# For each of 3 categories — extract → compile → sign.
SHA_BLOCK=""
SHA_NEVER=""
SHA_ALWAYS=""
SIZE_BLOCK=0
SIZE_NEVER=0
SIZE_ALWAYS=0

for category in block never always; do
    case "$category" in
        block)  key="block_completely" ;;
        never)  key="never_through_vpn" ;;
        always) key="always_through_vpn" ;;
    esac

    # Headless rule-set source-format per sing-box rule-set spec.
    # `version: 2` соответствует sing-box rule-set source-format version 2 (compiles to SRS binary).
    TMP_JSON="/tmp/bbtb-baseline-${category}-$$.json"
    jq --arg key "$key" '{
        version: 2,
        rules: [{
            domain: (.[$key].domains // []),
            domain_suffix: [],
            ip_cidr: (.[$key].ip_cidrs // [])
        }]
    }' "$BASELINE_JSON" > "$TMP_JSON"

    SRS_OUT="${RESOURCES}/bbtb-baseline-${category}.srs"
    SIG_OUT="${RESOURCES}/bbtb-baseline-${category}.srs.sig"

    # Compile JSON rule-set → SRS binary.
    sing-box rule-set compile --output "$SRS_OUT" "$TMP_JSON"
    SRS_SIZE=$(wc -c < "$SRS_OUT" | tr -d ' ')
    echo "Compiled: $(basename "$SRS_OUT") ($SRS_SIZE bytes)"

    # Detached Ed25519 signature.
    # Canonical form: `openssl pkeyutl -sign -rawin -inkey "$BBTB_BASELINE_SIGNING_KEY" -in <srs> -out <sig>`
    "$OPENSSL_BIN" pkeyutl -sign -rawin -inkey "$BBTB_BASELINE_SIGNING_KEY" \
        -in "$SRS_OUT" -out "$SIG_OUT"
    SIG_SIZE=$(wc -c < "$SIG_OUT" | tr -d ' ')
    echo "Signed:   $(basename "$SIG_OUT") ($SIG_SIZE bytes)"

    if [[ "$SIG_SIZE" != "64" ]]; then
        echo "ERROR: $(basename "$SIG_OUT") is $SIG_SIZE bytes (expected 64 for Ed25519)"
        exit 1
    fi

    SHA=$(shasum -a 256 "$SRS_OUT" | awk '{print $1}')
    case "$category" in
        block)  SHA_BLOCK="$SHA"; SIZE_BLOCK="$SRS_SIZE" ;;
        never)  SHA_NEVER="$SHA"; SIZE_NEVER="$SRS_SIZE" ;;
        always) SHA_ALWAYS="$SHA"; SIZE_ALWAYS="$SRS_SIZE" ;;
    esac

    rm -f "$TMP_JSON"
done

TOTAL_SIZE=$((SIZE_BLOCK + SIZE_NEVER + SIZE_ALWAYS))

# Read baseline.min_app_version for pass-through.
BASELINE_VERSION=$(jq -r '.version' "$BASELINE_JSON")
MIN_APP_VERSION=$(jq -r '.min_app_version' "$BASELINE_JSON")

# Build manifest JSON, embedding sha256 + size + CategoryBodies для UI snapshot.
jq -n \
    --argjson version "$BASELINE_VERSION" \
    --arg minAppVersion "$MIN_APP_VERSION" \
    --arg shaBlock "$SHA_BLOCK" --argjson sizeBlock "$SIZE_BLOCK" \
    --arg shaNever "$SHA_NEVER" --argjson sizeNever "$SIZE_NEVER" \
    --arg shaAlways "$SHA_ALWAYS" --argjson sizeAlways "$SIZE_ALWAYS" \
    --argjson totalSize "$TOTAL_SIZE" \
    --slurpfile baseline "$BASELINE_JSON" \
    '{
        version: $version,
        min_app_version: $minAppVersion,
        srs_format_version: 4,
        total_size_bytes: $totalSize,
        files: [
            {name: "bbtb-baseline-block.srs",  category: "block_completely",   sha256: $shaBlock,  sig_path: "bbtb-baseline-block.srs.sig",  size_bytes: $sizeBlock},
            {name: "bbtb-baseline-never.srs",  category: "never_through_vpn",  sha256: $shaNever,  sig_path: "bbtb-baseline-never.srs.sig",  size_bytes: $sizeNever},
            {name: "bbtb-baseline-always.srs", category: "always_through_vpn", sha256: $shaAlways, sig_path: "bbtb-baseline-always.srs.sig", size_bytes: $sizeAlways}
        ],
        block_completely:   $baseline[0].block_completely,
        never_through_vpn:  $baseline[0].never_through_vpn,
        always_through_vpn: $baseline[0].always_through_vpn
    }' > "$MANIFEST_OUT"

echo "Manifest written: $(basename "$MANIFEST_OUT") ($(wc -c < "$MANIFEST_OUT" | tr -d ' ') bytes)"

# Sign manifest LAST (last-write-fences-transaction per W2.3 DEC-08-W2-05).
# Canonical form: `openssl pkeyutl -sign -rawin -inkey "$BBTB_BASELINE_SIGNING_KEY" -in <manifest> -out <manifest.sig>`
"$OPENSSL_BIN" pkeyutl -sign -rawin -inkey "$BBTB_BASELINE_SIGNING_KEY" \
    -in "$MANIFEST_OUT" -out "$MANIFEST_SIG_OUT"
MANIFEST_SIG_SIZE=$(wc -c < "$MANIFEST_SIG_OUT" | tr -d ' ')
echo "Manifest signed: $(basename "$MANIFEST_SIG_OUT") ($MANIFEST_SIG_SIZE bytes)"

if [[ "$MANIFEST_SIG_SIZE" != "64" ]]; then
    echo "ERROR: manifest.sig is $MANIFEST_SIG_SIZE bytes (expected 64 for Ed25519)"
    exit 1
fi

# Ephemeral mode — derive corresponding public key + overwrite PublicKey.swift literal.
if [[ "$EPHEMERAL_MODE" == "1" ]]; then
    echo ""
    echo "Updating PublicKey.swift with ephemeral pubkey bytes…"
    # Ed25519 public key DER encoding: 12-byte prefix + 32 raw bytes (last 32 = raw pubkey).
    PUBKEY_HEX=$("$OPENSSL_BIN" pkey -in "$BBTB_BASELINE_SIGNING_KEY" -pubout -outform DER 2>/dev/null \
        | tail -c 32 | xxd -p | tr -d '\n')
    if [[ -z "$PUBKEY_HEX" ]] || [[ "${#PUBKEY_HEX}" -ne 64 ]]; then
        echo "ERROR: pubkey DER tail extraction failed (got ${#PUBKEY_HEX} hex chars, expected 64)"
        exit 1
    fi

    # Format как Swift array literal: 4 lines × 8 bytes.
    PUBKEY_SWIFT_LITERAL=""
    for row in 0 1 2 3; do
        line="        "
        for col in 0 1 2 3 4 5 6 7; do
            idx=$((row*8 + col))
            byte_hex="${PUBKEY_HEX:$((idx*2)):2}"
            byte_hex_upper=$(echo "$byte_hex" | tr '[:lower:]' '[:upper:]')
            line+="0x${byte_hex_upper}, "
        done
        # Trim trailing space (keep comma).
        line="${line% }"
        PUBKEY_SWIFT_LITERAL+="${line}"$'\n'
    done

    # Rewrite the publicKeyBytes literal in PublicKey.swift via Python (portable
    # in-place replace; sed multiline regex is fragile across BSD/GNU).
    python3 - <<PYEOF
import io, re, sys
path = "$PUBKEY_SWIFT"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()
new_block = """$PUBKEY_SWIFT_LITERAL"""
# new_block ends with trailing newline — that's expected inside [ ... ].
pattern = re.compile(
    r"(private static let publicKeyBytes: \[UInt8\] = \[\n)(.*?)(\n    \])",
    re.DOTALL,
)
m = pattern.search(src)
if not m:
    print("ERROR: could not locate publicKeyBytes literal in PublicKey.swift", file=sys.stderr)
    sys.exit(1)
# new_block already has 4 indented lines с trailing newlines — strip final \n
# so the close bracket alignment stays at "    ]".
replacement = m.group(1) + new_block.rstrip("\n") + m.group(3)
src2 = pattern.sub(replacement, src, count=1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src2)
PYEOF

    # Sanity: placeholder 0x00, 0x01, 0x02, 0x03 sequence must be gone.
    if grep -E "0x00,\s*0x01,\s*0x02,\s*0x03" "$PUBKEY_SWIFT" >/dev/null 2>&1; then
        echo "ERROR: placeholder 0x00, 0x01, 0x02, 0x03 sequence still present in PublicKey.swift"
        echo "       PublicKey.swift rewrite failed."
        exit 1
    fi
    echo "PublicKey.swift updated: placeholder sequence absent."
fi

echo ""
echo "✓ Build complete. Files in $RESOURCES:"
ls -la "$RESOURCES"/{baseline-rules.json,baseline-rules-manifest.json,baseline-rules-manifest.json.sig,bbtb-baseline-block.srs,bbtb-baseline-block.srs.sig,bbtb-baseline-never.srs,bbtb-baseline-never.srs.sig,bbtb-baseline-always.srs,bbtb-baseline-always.srs.sig} 2>/dev/null
