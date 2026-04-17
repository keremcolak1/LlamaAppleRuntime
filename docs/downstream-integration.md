# Downstream Integration Plan

This runtime package should not be wired into a production app until it has produced a tested release artifact.

## Current Downstream State

Many local llama.cpp app integrations use:

- A binary target for the upstream llama.cpp XCFramework.
- An app-owned C++ bridge target.
- A temporary vendored mtmd source path under that bridge.

That temporary bridge path remains in place until `LlamaApple.xcframework` exports mtmd.

## Future Downstream State

After the first tested release:

1. Replace the current `llama-cpp` binary target URL with this package's release URL, or consume this package as a separate SwiftPM package dependency.
2. Remove `upstream/tools/mtmd` from the downstream package manifest.
3. Remove mtmd header search paths that point into a local vendored upstream tree.
4. Keep the app-owned bridge code in the downstream app.
5. Include only app-owned bridge code and any minimal upstream common headers that are still truly required.
6. Build the downstream app and run the image flow on device.

## Success Criteria

A downstream app is ready to delete its temporary vendored mtmd path when:

- `LlamaApple.xcframework.zip` resolves through SwiftPM.
- The app-owned bridge can include `mtmd.h` and `mtmd-helper.h` from the binary framework.
- The downstream package builds for iOS device and simulator.
- A vision model with a companion mmproj asset runs on device.
- Updating llama.cpp means updating this runtime package release, not editing app source.
