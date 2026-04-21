# GoPro 360 Stitcher (Apple Silicon M4 Optimized)

A high-performance native macOS application designed to ingest, stitch, reframe, and export GoPro MAX `.360` files directly on Apple Silicon.

## 🚀 Native Architecture
- **Language:** Swift 6 (Strict Concurrency)
- **UI:** SwiftUI
- **Processing:** AVFoundation + Metal Compute Shaders
- **Optimization:** M4 Media Engine (Hardware HEVC Encoding)

## ✨ Key Features
- **Virtual Stitching:** Automatically identifies and sequentializes chaptered GoPro `.360` files without re-encoding until final export.
- **Dual-Track Decoding:** Extracts both Track 0 (Front Lens) and Track 5 (Back Lens) spherical video tracks from the `.360` container.
- **Pixel-Perfect EAC Unwarping:** Features a highly optimized Metal compute shader that precisely mirrors the official GoPro MAX Equi-Angular Cubemap (EAC) algebra.
  - Automatically handles the proprietary 3x2 face atlas mapping (with tracks split).
  - Handles the complex `ROT_90` and `ROT_270` mappings to correct the Rear, Top, and Bottom faces without geometric folding.
  - Perfectly aligns the 64-pixel seam overlaps at exactly `x=688` and `x=3280` cuts.
- **Interactive 360 Viewer:** Produces a seamless spherical view of the 360 world with Pan, Tilt, Roll, and Zoom controls.
- **Telemetry Integration:** Stub exists for GPMF telemetry extraction to draw GPS track maps (Work in progress).

## 🛠 Symlink Workaround
Since `AVFoundation` does not natively recognize the `.360` file extension as a valid media container, this application implements a robust **Symlink Proxy Strategy**:
1. Files are selected via Drag & Drop or File Picker.
2. The app creates a temporary `.mp4` symlink for each `.360` file in the system temp directory.
3. `AVURLAsset` consumes the symlink, successfully bypassing extension-based format checks while maintaining zero-copy data access.

## 🏃 Running the App
### Prerequisites
- macOS 14.0+ (Sonoma or later)
- Xcode 15+ (or Swift Command Line Tools)
- Apple Silicon (M4 recommended for peak performance)

### Build
```bash
make build
```

### Run
```bash
make run
```

### Headless End-to-End Test
To verify the engine without the UI:
```bash
./.build/release/GoPro360Stitcher --test-file "/path/to/your/file.360"
```

## 📂 Project Structure
- `VideoProcessor.swift`: The engine that manages the virtual timeline and export session.
- `EACCompositor.swift`: Custom `AVVideoCompositing` class that bridges AVFoundation to Metal.
- `EACRenderer.swift`: Metal pipeline manager that handles textures and compute encoders.
- `EACShader.metal`: High-performance compute shader for spherical-to-rectilinear projection.
- `GPMFParser.swift`: Telemetry extraction logic.

## 🗺 Roadmap
- [ ] **UI Progress Reporting:** Add real-time progress bars for export and batch operations.
- [ ] **Advanced Export Controls:** Selection for output resolution (up to 5.6K), bitrate, and HEVC/ProRes encoding profiles.
- [ ] **Batch Processing Queue:** Ability to queue multiple `.360` files for headless background stitching and export.
- [ ] **State Persistence:** Automatically save and restore Pan, Tilt, Roll, and Zoom settings per file.
- [ ] **Telemetry Visualizations:** Dynamic GPS maps, speedometers, and G-force gauges overlaid on the video using GPMF data.
- [ ] **Spatial Audio (Ambisonics):** Proper mapping of GoPro's 4-channel ambisonic audio to a spatialized 360 soundscape.
- [ ] **Keyframe Re-framing:** Implement a timeline to animate camera movements (Pan/Tilt) for cinematic exported shots.
- [ ] **AI Super-Resolution:** Integrate CoreML for hardware-accelerated upscaling during the export pipeline.
