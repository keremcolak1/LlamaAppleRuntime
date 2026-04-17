#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/runtime.sh
source "$ROOT/scripts/lib/runtime.sh"

load_runtime_config "$ROOT"

VERSION="$LLAMA_APPLE_RELEASE_VERSION"

usage() {
    cat <<'USAGE'
Usage: scripts/package-release.sh [--version <version>]

Zips artifacts/LlamaApple.xcframework, computes the SwiftPM checksum, and writes
metadata/current-release.json.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

require_command swift

ARTIFACTS="$(artifact_dir "$ROOT")"
XCFRAMEWORK="$ARTIFACTS/$LLAMA_APPLE_FRAMEWORK_NAME.xcframework"
ZIP_PATH="$ARTIFACTS/$LLAMA_APPLE_ZIP_NAME"
METADATA_PATH="$ROOT/metadata/current-release.json"

[[ -d "$XCFRAMEWORK" ]] || die "missing XCFramework: $XCFRAMEWORK"

rm -f "$ZIP_PATH"

if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK" "$ZIP_PATH"
else
    require_command zip
    (
        cd "$ARTIFACTS"
        zip -qry "$ZIP_PATH" "$LLAMA_APPLE_FRAMEWORK_NAME.xcframework"
    )
fi

CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"

mkdir -p "$(dirname "$METADATA_PATH")"
cat > "$METADATA_PATH" <<JSON
{
  "version": "$VERSION",
  "upstreamRepository": "$LLAMA_CPP_REPOSITORY",
  "upstreamRevision": "$LLAMA_CPP_REVISION",
  "artifact": "$LLAMA_APPLE_ZIP_NAME",
  "checksum": "$CHECKSUM"
}
JSON

log "packaged $ZIP_PATH"
log "checksum $CHECKSUM"
log "metadata $METADATA_PATH"

cat <<MESSAGE

SwiftPM binary target values:
  url:      https://github.com/OWNER/LlamaAppleRuntime/releases/download/$VERSION/$LLAMA_APPLE_ZIP_NAME
  checksum: $CHECKSUM
MESSAGE

