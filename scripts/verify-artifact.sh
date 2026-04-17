#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/runtime.sh
source "$ROOT/scripts/lib/runtime.sh"

load_runtime_config "$ROOT"

usage() {
    cat <<'USAGE'
Usage: scripts/verify-artifact.sh <path-to-xcframework-or-zip>

Verifies that the runtime artifact contains the public headers downstream consumers need.
When framework binaries are present, also verifies the required exported symbols.
USAGE
}

[[ $# -eq 1 ]] || {
    usage
    exit 2
}

INPUT="$1"
TMP_DIR=""
BINARY_LIST=""

cleanup() {
    if [[ -n "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
    if [[ -n "$BINARY_LIST" ]]; then
        rm -f "$BINARY_LIST"
    fi
}
trap cleanup EXIT

if [[ -d "$INPUT" ]]; then
    XCFRAMEWORK="$INPUT"
elif [[ -f "$INPUT" ]]; then
    require_command unzip
    TMP_DIR="$(mktemp -d)"
    unzip -q "$INPUT" -d "$TMP_DIR"
    XCFRAMEWORK="$(find "$TMP_DIR" -maxdepth 2 -name "$LLAMA_APPLE_FRAMEWORK_NAME.xcframework" -type d | head -n 1)"
else
    die "artifact does not exist: $INPUT"
fi

[[ -n "${XCFRAMEWORK:-}" && -d "$XCFRAMEWORK" ]] || die "could not find $LLAMA_APPLE_FRAMEWORK_NAME.xcframework"

MISSING=0
while IFS= read -r header; do
    [[ -z "$header" || "$header" == \#* ]] && continue

    if find "$XCFRAMEWORK" -path "*/Headers/$header" -type f | grep -q .; then
        log "found header: $header"
    else
        printf '[LlamaAppleRuntime] missing header: %s\n' "$header" >&2
        MISSING=1
    fi
done < "$ROOT/config/public-headers.txt"

if [[ "$MISSING" -ne 0 ]]; then
    die "artifact is missing required public headers"
fi

cat <<'MESSAGE'
[LlamaAppleRuntime] header verification passed

MESSAGE

if command -v nm >/dev/null 2>&1 && [[ -f "$ROOT/config/public-symbols.txt" ]]; then
    BINARY_LIST="$(mktemp)"
    find "$XCFRAMEWORK" -path "*/$LLAMA_APPLE_FRAMEWORK_NAME.framework/$LLAMA_APPLE_FRAMEWORK_NAME" -type f > "$BINARY_LIST"

    if [[ ! -s "$BINARY_LIST" ]]; then
        log "symbol verification skipped; no framework binaries found"
        exit 0
    fi

    SYMBOL_MISSING=0
    while IFS= read -r symbol; do
        [[ -z "$symbol" || "$symbol" == \#* ]] && continue

        # Avoid `grep -q` here: with `set -o pipefail`, an early grep exit can
        # make a successful nm run look like a failure if nm receives SIGPIPE.
        if xargs nm -gU < "$BINARY_LIST" 2>/dev/null |
            grep -E "(^|[[:space:]])_?${symbol}$" >/dev/null; then
            log "found symbol: $symbol"
        else
            printf '[LlamaAppleRuntime] missing symbol: %s\n' "$symbol" >&2
            SYMBOL_MISSING=1
        fi
    done < "$ROOT/config/public-symbols.txt"

    if [[ "$SYMBOL_MISSING" -ne 0 ]]; then
        die "artifact is missing required public symbols"
    fi

    log "symbol verification passed"
else
    log "symbol verification skipped"
fi
