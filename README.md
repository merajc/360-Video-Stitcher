# 360 Video Stitcher

A native macOS app for stitching, reframing and exporting GoPro MAX `.360` footage — Swift, AVFoundation and Metal, with no ffmpeg, no Python and no GoPro app in the pipeline.

> The product is named **360 Video Stitcher**; the executable and app bundle are still built as `GoPro360Stitcher` (see [Build and run](#build-and-run)).

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What it does

- **Chapter stitching** — sequential `.360` files are assembled into one virtual timeline. Nothing is re-encoded until you export.
- **Spherical unwarping** — a Metal compute shader maps both spherical tracks (front and rear) out of GoPro MAX's equi-angular cubemap (EAC) layout: the 3×2 face atlas with tracks split, `ROT_90`/`ROT_270` for the rear/top/bottom faces, and the 64-pixel seam overlaps at `x=688` and `x=3280` in the 4096-wide source.
- **Two independent views** — the output canvas is split into a top and bottom reframed view, each with its own pan, tilt, roll, field of view and flips.
- **Telemetry overlays** — GPS track map, speed, altitude and 3-axis G-force, extracted from the camera's GPMF metadata (no external tooling).
- **Export options** — 1080p / 4K / 5.6K, HEVC or ProRes 422, selectable bitrate, and a batch queue.

## Requirements

| | |
|---|---|
| OS | macOS 14 (Sonoma) or later |
| Hardware | Apple Silicon |
| Toolchain | Swift 6 — Xcode 16+ or the Swift toolchain from Command Line Tools |
| Input | GoPro MAX `.360` files (other 360 cameras are untested) |

You do **not** need to download Apple's optional "Metal Toolchain" component (Xcode 26+). The shader ships as a plain resource and is compiled at runtime by `MTLLibrary.makeLibrary(source:)`, so a stock Swift toolchain is enough to build and run.

## Build and run

```bash
make build     # release build
make run       # build and launch
make bundle    # package GoPro360Stitcher.app (ad-hoc signed)
make install   # build, bundle and copy to /Applications
```

`make bundle` produces a self-contained `GoPro360Stitcher.app` with the shader resource embedded. It is signed ad-hoc, so it runs on the machine that built it; distributing it to other Macs requires your own Developer ID signature and notarisation.

## Headless export

Useful for scripting and for checking the engine end-to-end without the UI:

```bash
./.build/release/GoPro360Stitcher \
    --test-file "/path/to/GH010001.360" \
    --output "/path/to/output.mp4" \
    --test-duration 15
```

- `--test-file` — the chapter to process (additional chapters in the same folder are stitched if you pass them via the UI).
- `--output` — optional. Defaults to `<clip>_stitched.mp4` next to the source, or `~/Movies/` if that location is read-only.
- `--test-duration` — optional. Exports only the first *N* seconds; omit for the full clip.

The command exits `0` on success and `1` on failure, and prints progress to stdout.

## Logging

Diagnostics go to the unified log at `debug` level, so they stay out of the way during normal use:

```bash
log stream --predicate 'subsystem == "com.merajc.GoPro360Stitcher"' --level debug
```

Errors that reach the UI are also written at `error` level.

## Why the symlink dance?

`AVFoundation` refuses to open a file whose extension is `.360`. The app creates a temporary `.mp4` symlink for each chapter and hands that to `AVURLAsset`, which bypasses the extension-based check without copying any data.

## How the audio works

GoPro MAX writes a 4-channel first-order Ambisonics (B-format) track alongside a stereo track.

- **ProRes 422 (.mov)** — the 4-channel B-format stream is written through intact, with the correct `Ambisonic_B_Format` channel layout. Use this if you plan to spatialise the audio later.
- **HEVC (.mp4)** — AAC in MP4 is stereo only here, so the export is 2-channel. The UI states this next to the audio toggle.

The app does not perform binaural/spatial rendering itself; it preserves or downmixes the ambisonic stream.

## Known limitations

- Exports are fixed at **30 fps**, regardless of the source frame rate.
- Overlay compositing renders the SwiftUI overlay on the main thread for each exported frame. It is correct, but with overlays enabled the export is meaningfully slower than a bare encode.
- The preview renders at the selected **export** resolution, so a 4K or 5.6K preview is heavier than it needs to be.
- Chapters are ordered by file creation date, with a filename fallback. If you copy files in a way that rewrites creation dates, verify the order in the timeline before exporting.
- HEVC/MP4 cannot carry the 4-channel ambisonic stream (see above).

## Project structure

| File | Role |
|---|---|
| `VideoProcessor.swift` | Virtual timeline, reframing state, export job setup |
| `ExportPipeline.swift` | Reader/writer pump, overlay compositing, cancellation |
| `EACCompositor.swift` | `AVVideoCompositing` bridge between AVFoundation and Metal |
| `EACRenderer.swift` | Metal device, pipeline and texture cache |
| `EACShader.msl` | EAC unwarp compute kernel (compiled at runtime) |
| `GPMFParser.swift` | GPMF/KLV telemetry extraction |
| `MP4BoxParser.swift` | Minimal MP4 box parser for the GPMF track |
| `TelemetryProcessor.swift` | GPS/IMU processing, G-force derivation |
| `ContentView.swift` | SwiftUI interface |

## Roadmap

- [x] Real-time progress reporting for export and batch operations
- [x] Output resolution, bitrate and codec selection (HEVC / ProRes 422)
- [x] Continuous multi-chapter stitching
- [x] Batch export queue
- [x] Persisted pan / tilt / roll / FOV state
- [x] GPS, speed, altitude and G-force overlays from GPMF
- [x] 4-channel Ambisonics preserved in ProRes output
- [x] Close the current clip and open another without relaunching
- [ ] Per-clip settings and info within a stitched timeline
- [ ] Queue management: remove items, parallel processing
- [ ] Drag-and-drop gauge positioning on the player
- [ ] Gesture-based reframing on the player
- [ ] CoreML super-resolution in the export pipeline

## License

[MIT](LICENSE) © 2026 Meraj Chhaya

Not affiliated with, endorsed by or supported by GoPro, Inc. "GoPro" and "MAX" are trademarks of GoPro, Inc.
