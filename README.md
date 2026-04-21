# GoPro 360 Stitcher (Apple Silicon M4 Optimized)

A high-performance native macOS application designed to ingest, stitch, reframe, and export GoPro MAX `.360` files directly on Apple Silicon.

## 🚀 Native Architecture
- **Language:** Swift 6 (Strict Concurrency)
- **UI:** SwiftUI
- **Processing:** AVFoundation + Metal Compute Shaders
- **Optimization:** M4 Media Engine (Hardware HEVC Encoding)

## ✨ Key Features
- **Virtual Stitching:** Automatically identifies and sequentializes chaptered GoPro `.360` files without re-encoding until final export.
- **Dual-Track Processing:** Extracts both Front and Rear hemispherical video tracks from the GoPro container.
- **EAC Projection:** Uses a custom Metal-based Equi-Angular Cubemap (EAC) compositor to project spherical footage into rectilinear frames.
- **Vertical Stack Export:** Produces a 9:16 vertical video containing a stacked view of both Front and Rear cameras, perfect for social media or track-day analysis.
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
