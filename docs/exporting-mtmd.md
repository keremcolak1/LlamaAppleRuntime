# Exporting mtmd

The custom XCFramework must expose the native API surface a downstream bridge needs. It is not enough for mtmd to exist in the upstream checkout; the final framework slices must make the headers and symbols visible to downstream SwiftPM consumers.

## Required Headers

The initial required public header list lives in `config/public-headers.txt`:

- `llama.h`
- `ggml.h`
- `gguf.h`
- `mtmd.h`
- `mtmd-helper.h`

As downstream bridge requirements evolve, update that file first, then make the build output satisfy it.

## Required Symbols

The exact list should be validated against the downstream bridge when the framework build is implemented. The first pass should include at least:

- `llama_backend_init`
- `llama_backend_free`
- `mtmd_context_params_default`
- `mtmd_init_from_file`
- `mtmd_free`
- `mtmd_tokenize`
- `mtmd_helper_eval_chunks`
- `mtmd_helper_bitmap_init_from_file`

## Framework Contract

Each XCFramework slice should contain:

- A framework binary that links llama, ggml, gguf, and mtmd code.
- Public headers under `Headers/`.
- A module map that exposes those headers to C, C++, Objective-C, and SwiftPM targets.
- Architectures needed by supported downstream platforms.

## Build Path

The build script follows upstream llama.cpp's XCFramework pattern, with package-specific changes:

- It fetches a pinned source archive instead of tracking upstream master.
- It configures CMake with `LLAMA_BUILD_TOOLS=ON` so `tools/mtmd` is part of the generated project.
- It builds the `mtmd` target directly instead of building every llama.cpp tool.
- It combines `libllama.a`, ggml static libraries, and `libmtmd.a` into the framework binary.
- It copies `mtmd.h` and `mtmd-helper.h` into every framework slice.
- It verifies required headers and symbols before release packaging.

The default build matrix is iOS device plus iOS Simulator. A macOS slice can be requested with `--platforms ios-device,ios-simulator,macos`.
