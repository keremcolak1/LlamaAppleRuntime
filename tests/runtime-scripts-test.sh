#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'expected output to contain: %s\n' "$needle" >&2
        printf 'actual output:\n%s\n' "$haystack" >&2
        exit 1
    fi
}

test_build_script_dry_run_documents_mtmd_contract() {
    local output
    output="$("$ROOT/scripts/build-xcframework.sh" --dry-run --skip-bootstrap 2>&1)"

    assert_contains "$output" "LlamaApple.xcframework"
    assert_contains "$output" "mtmd"
    assert_contains "$output" "-DLLAMA_BUILD_TOOLS=ON"
    assert_contains "$output" "tools/mtmd/mtmd.h"
    assert_contains "$output" "xcodebuild -create-xcframework"
}

test_bootstrap_metadata_documents_archive_fetch_mode() {
    local output
    output="$("$ROOT/scripts/bootstrap-upstream.sh" --metadata-only --fetch-mode archive 2>&1)"

    assert_contains "$output" "fetch mode: archive"
}

test_verify_artifact_accepts_required_public_headers() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    local headers_dir="$tmp_dir/LlamaApple.xcframework/ios-arm64/LlamaApple.framework/Headers"
    mkdir -p "$headers_dir"

    while IFS= read -r header; do
        [[ -z "$header" || "$header" == \#* ]] && continue
        printf '/* test header */\n' > "$headers_dir/$header"
    done < "$ROOT/config/public-headers.txt"

    "$ROOT/scripts/verify-artifact.sh" "$tmp_dir/LlamaApple.xcframework" >/dev/null
}

test_verify_artifact_symbol_check_handles_pipeline_completion() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    local headers_dir="$tmp_dir/LlamaApple.xcframework/ios-arm64/LlamaApple.framework/Headers"
    local binary_path="$tmp_dir/LlamaApple.xcframework/ios-arm64/LlamaApple.framework/LlamaApple"
    local fake_bin_dir="$tmp_dir/fake-bin"

    mkdir -p "$headers_dir" "$fake_bin_dir"
    touch "$binary_path"

    while IFS= read -r header; do
        [[ -z "$header" || "$header" == \#* ]] && continue
        printf '/* test header */\n' > "$headers_dir/$header"
    done < "$ROOT/config/public-headers.txt"

    cat > "$fake_bin_dir/nm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'OUT'
0000000000000000 T _llama_backend_init
0000000000000000 T _llama_backend_free
0000000000000000 T _mtmd_context_params_default
0000000000000000 T _mtmd_init_from_file
0000000000000000 T _mtmd_free
0000000000000000 T _mtmd_tokenize
0000000000000000 T _mtmd_helper_eval_chunks
0000000000000000 T _mtmd_helper_bitmap_init_from_file
OUT

i=0
while [[ "$i" -lt 2000 ]]; do
    i=$((i + 1))
    printf '0000000000000000 T _filler_%s\n' "$i"
done
EOF
    chmod +x "$fake_bin_dir/nm"

    PATH="$fake_bin_dir:$PATH" "$ROOT/scripts/verify-artifact.sh" "$tmp_dir/LlamaApple.xcframework" >/dev/null
}

test_build_script_dry_run_documents_mtmd_contract
test_bootstrap_metadata_documents_archive_fetch_mode
test_verify_artifact_accepts_required_public_headers
test_verify_artifact_symbol_check_handles_pipeline_completion

printf 'runtime script tests passed\n'
