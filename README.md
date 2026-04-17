# LlamaAppleRuntime

Apple XCFramework packaging for llama.cpp with `mtmd` exposed.

## Why This Exists

The upstream llama.cpp repo has `mtmd`, and source/CMake installs can expose `mtmd.h` and `mtmd-helper.h`.

The Apple XCFramework release is different: it only exposes the headers that were packaged into that binary framework. The public llama.cpp XCFramework did not give us the `mtmd` headers we needed for vision support in an Xcode/SwiftPM app.

This repo builds a custom `LlamaApple.xcframework` so downstream apps can import one binary package that exposes llama.cpp plus the multimodal `mtmd` surface.

## What It Builds

- `LlamaApple.xcframework`
- iOS device and iOS Simulator slices by default
- public headers for `llama`, `ggml`, `gguf`, and `mtmd`
- a SwiftPM `binaryTarget` package manifest

## Quick Start

```sh
scripts/bootstrap-upstream.sh
scripts/build-xcframework.sh
scripts/package-release.sh --version 0.1.0
scripts/verify-artifact.sh artifacts/LlamaApple.xcframework.zip
```

The build needs Xcode command line tools and CMake.

## Updating llama.cpp

Do not follow upstream master automatically. Pick a specific llama.cpp tag or commit, update `config/upstream.env`, build, test, then publish a release.

The intended release loop is:

1. Pin an upstream revision.
2. Build the XCFramework.
3. Verify required headers and symbols.
4. Test in a real downstream app.
5. Publish `LlamaApple.xcframework.zip`.
6. Update `Package.swift` with the release URL and checksum.

## Repository Layout

```text
Package.swift
config/
scripts/
metadata/
docs/
artifacts/
.github/workflows/
```

`artifacts/` is for local build output and is ignored except for `.gitkeep`.

## License

This repository is MIT licensed. Release artifacts may include compiled llama.cpp code from https://github.com/ggml-org/llama.cpp, which is also MIT licensed by the ggml authors and contributors. See `NOTICE.md`.

