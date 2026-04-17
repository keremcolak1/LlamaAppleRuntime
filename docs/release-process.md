# Release Process

The runtime should be released deliberately. Do not auto-follow llama.cpp master.

## 1. Choose an Upstream Revision

Pick a specific llama.cpp tag or commit. Prefer a known release tag when possible.

Update `config/upstream.env`:

```sh
LLAMA_CPP_REVISION=b8827
```

## 2. Bootstrap Source

```sh
scripts/bootstrap-upstream.sh --reset
```

## 3. Build the XCFramework

```sh
scripts/build-xcframework.sh
```

This requires CMake and Xcode command line tools. The default build produces iOS device and iOS Simulator slices.

## 4. Package and Checksum

```sh
scripts/package-release.sh --version 0.1.0
```

This creates:

- `artifacts/LlamaApple.xcframework.zip`
- `metadata/current-release.json`

## 5. Verify Artifact

```sh
scripts/verify-artifact.sh artifacts/LlamaApple.xcframework.zip
```

Header verification exists now. Symbol verification should be added once the final framework layout is known.

## 6. Test With A Downstream App

Before publishing a release as ready for consumers:

- Build a downstream app or package for iOS device and simulator.
- Run the downstream app's automated tests.
- Run the downstream app on a physical device with a text-only model.
- Run the downstream app on a physical device with a vision model and companion mmproj asset.
- Confirm image inference works and text-only inference still works.

## 7. Publish GitHub Release

Attach `LlamaApple.xcframework.zip` to a versioned GitHub release. Then copy the release URL and checksum into `Package.swift`.

## 8. Update Consumers

Only after the release is tested:

1. Update downstream packages to consume the new binary target.
2. Remove the temporary vendored mtmd source dependency.
3. Build and test each downstream consumer again.
