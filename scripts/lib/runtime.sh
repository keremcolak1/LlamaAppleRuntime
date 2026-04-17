#!/usr/bin/env bash
set -euo pipefail

runtime_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$script_dir/.." && pwd
}

log() {
    printf '[LlamaAppleRuntime] %s\n' "$*"
}

die() {
    printf '[LlamaAppleRuntime] error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "missing required command: $1"
    fi
}

load_runtime_config() {
    local root="$1"
    local config_file="$root/config/upstream.env"

    [[ -f "$config_file" ]] || die "missing config file: $config_file"

    # shellcheck disable=SC1090
    source "$config_file"

    if [[ -n "${LLAMA_APPLE_OVERRIDE_REVISION:-}" ]]; then
        LLAMA_CPP_REVISION="$LLAMA_APPLE_OVERRIDE_REVISION"
    fi

    if [[ -n "${LLAMA_APPLE_OVERRIDE_RELEASE_VERSION:-}" ]]; then
        LLAMA_APPLE_RELEASE_VERSION="$LLAMA_APPLE_OVERRIDE_RELEASE_VERSION"
    fi

    : "${LLAMA_CPP_REPOSITORY:?missing LLAMA_CPP_REPOSITORY in config/upstream.env}"
    : "${LLAMA_CPP_REVISION:?missing LLAMA_CPP_REVISION in config/upstream.env}"
    : "${LLAMA_APPLE_PRODUCT_NAME:?missing LLAMA_APPLE_PRODUCT_NAME in config/upstream.env}"
    : "${LLAMA_APPLE_FRAMEWORK_NAME:?missing LLAMA_APPLE_FRAMEWORK_NAME in config/upstream.env}"
    : "${LLAMA_APPLE_ZIP_NAME:?missing LLAMA_APPLE_ZIP_NAME in config/upstream.env}"
    : "${LLAMA_APPLE_RELEASE_VERSION:?missing LLAMA_APPLE_RELEASE_VERSION in config/upstream.env}"
}

upstream_checkout_dir() {
    local root="$1"
    printf '%s\n' "${LLAMA_APPLE_UPSTREAM_DIR:-$root/.build/upstream/llama.cpp}"
}

artifact_dir() {
    local root="$1"
    printf '%s\n' "${LLAMA_APPLE_ARTIFACT_DIR:-$root/artifacts}"
}
