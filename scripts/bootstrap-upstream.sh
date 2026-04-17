#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/runtime.sh
source "$ROOT/scripts/lib/runtime.sh"

load_runtime_config "$ROOT"

REVISION="$LLAMA_CPP_REVISION"
FETCH_MODE="${LLAMA_APPLE_FETCH_MODE:-archive}"
METADATA_ONLY=0
RESET_CHECKOUT=0
BOOTSTRAP_TMP_DIR=""

cleanup_bootstrap() {
    if [[ -n "$BOOTSTRAP_TMP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_TMP_DIR"
    fi
}
trap cleanup_bootstrap EXIT

usage() {
    cat <<'USAGE'
Usage: scripts/bootstrap-upstream.sh [--revision <tag-or-commit>] [--fetch-mode archive|git] [--metadata-only] [--reset]

Fetches the pinned llama.cpp source into .build/upstream/llama.cpp.

Options:
  --revision <value>   Override LLAMA_CPP_REVISION for this run.
  --fetch-mode <mode>  Use a GitHub source archive or a git checkout. Default: archive.
  --metadata-only      Print resolved config without network access.
  --reset              Remove the existing checkout before fetching.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --revision)
            [[ $# -ge 2 ]] || die "--revision requires a value"
            REVISION="$2"
            shift 2
            ;;
        --fetch-mode)
            [[ $# -ge 2 ]] || die "--fetch-mode requires archive or git"
            FETCH_MODE="$2"
            shift 2
            ;;
        --metadata-only)
            METADATA_ONLY=1
            shift
            ;;
        --reset)
            RESET_CHECKOUT=1
            shift
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

CHECKOUT_DIR="$(upstream_checkout_dir "$ROOT")"
REVISION_FILE="$CHECKOUT_DIR/.llama-apple-revision"

log "repository: $LLAMA_CPP_REPOSITORY"
log "revision:   $REVISION"
log "fetch mode: $FETCH_MODE"
log "checkout:   $CHECKOUT_DIR"

if [[ "$METADATA_ONLY" -eq 1 ]]; then
    exit 0
fi

if [[ "$RESET_CHECKOUT" -eq 1 && -d "$CHECKOUT_DIR" ]]; then
    log "removing existing checkout"
    rm -rf "$CHECKOUT_DIR"
fi

if [[ -f "$REVISION_FILE" ]] && [[ "$(cat "$REVISION_FILE")" == "$REVISION" ]]; then
    log "existing checkout already matches requested revision"
    exit 0
fi

fetch_archive() {
    require_command curl
    require_command tar

    local archive_path
    local source_parent
    local source_root
    local repository_base

    BOOTSTRAP_TMP_DIR="$(mktemp -d)"
    archive_path="$BOOTSTRAP_TMP_DIR/llama.cpp.tar.gz"
    source_parent="$BOOTSTRAP_TMP_DIR/source"
    repository_base="${LLAMA_CPP_REPOSITORY%.git}"

    log "downloading source archive"
    curl -fL "$repository_base/archive/$REVISION.tar.gz" -o "$archive_path"

    mkdir -p "$source_parent"
    tar -xzf "$archive_path" -C "$source_parent"
    source_root="$(find "$source_parent" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [[ -n "$source_root" && -d "$source_root" ]] || die "could not unpack source archive"

    rm -rf "$CHECKOUT_DIR"
    mkdir -p "$(dirname "$CHECKOUT_DIR")"
    mv "$source_root" "$CHECKOUT_DIR"
}

fetch_git() {
    require_command git

    if [[ ! -d "$CHECKOUT_DIR/.git" ]]; then
        rm -rf "$CHECKOUT_DIR"
        mkdir -p "$(dirname "$CHECKOUT_DIR")"
        log "cloning llama.cpp"
        git clone "$LLAMA_CPP_REPOSITORY" "$CHECKOUT_DIR"
    fi

    log "fetching upstream revision"
    git -C "$CHECKOUT_DIR" fetch --tags --prune origin

    log "checking out $REVISION"
    git -C "$CHECKOUT_DIR" checkout --detach "$REVISION"

    log "syncing submodules"
    git -C "$CHECKOUT_DIR" submodule update --init --recursive
}

case "$FETCH_MODE" in
    archive) fetch_archive ;;
    git) fetch_git ;;
    *) die "unsupported fetch mode: $FETCH_MODE" ;;
esac

printf '%s\n' "$REVISION" > "$REVISION_FILE"

log "ready"
