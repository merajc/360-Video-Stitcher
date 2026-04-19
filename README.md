# GoPro 360 Stitcher (Apple Silicon Optimized)

A high-performance, native macOS application designed for GoPro MAX `.360` files. This app provides a seamless, M4-optimized pipeline for virtually stitching chaptered files, real-time reframing via Metal-accelerated EAC projection, and telemetry-overlayed exports.

## 🌟 Key Features

- **Virtual Stitching**: Chunks chaptered `.360` files (e.g., `GS010001.360`, `GS010002.360`) into a single continuous timeline using `AVMutableComposition` without intermediate disk writes.
- **Metal 3 Projection Engine**: Uses a custom compute shader (`EACShader.metal`) to transform Equi-Angular Cubemap (EAC) footage into rectilinear projection in real-time.
- **Stacked Dual-View**: Automatically generates a 9:16 vertical video with a Front-view (0°) and Rear-view (180°) stacked layout.
- **GPMF Telemetry Extraction**: Parses embedded GoPro metadata tracks (`gpmd`) to extract GPS coordinates and draw a 2D track map overlay.
- **M4 Media Engine Acceleration**: Built to utilize the latest Apple Silicon hardware for ultra-fast HEVC/H.265 encoding via `AVAssetExportSession`.
- **Glassmorphic UI**: A premium, "Swiftly" native SwiftUI interface with animated reframe controls (Pan, Tilt, Roll).

## 🚀 How It Works

### 1. Ingestion & Sorting
Files are dropped into the app. The `VideoProcessor` filters for `.360` files and automatically sorts them by creation date to reconstruct the sequence of chapters correctly.

### 2. Virtual Composition
Instead of merging files on disk (which takes time and space), we create an `AVMutableComposition`. This is a "virtual file" that points to the data in the original files, allowing instant playback across chapter boundaries.

### 3. EAC Geometry Transform
GoPro MAX files are stored in EAC format. Our Metal renderer samples this input, applies Pan/Tilt/Roll rotations, and projects it onto a flat plane. The vertical stack is created by sampling the spherical data twice: once for the front 180° and once for the rear 180°.

### 4. Telemetry Parsing
The `GPMFParser` looks for the `gpmd` track in the video containers. It parses the KLV (Key-Length-Value) blocks to find `GPS5` data. This data is then normalized and passed to `TrackMapOverlay` to render a 2D path using Core Graphics.

## 🛠 Build & Development

This project is configured to build entirely from the terminal, avoiding heavy Xcode dependencies.

### Requirements:
- macOS (Apple Silicon recommended)
- Swift 6.0+

### Usage:
1. **Build**: `make build`
2. **Run**: `make run`
3. **Clean**: `make clean`

## 📂 Project Structure

- `Sources/GoPro360Stitcher/`
  - `GoPro360StitcherApp.swift`: App Entry point.
  - `ContentView.swift`: Main UI and Glassmorphic controls.
  - `VideoProcessor.swift`: AVFoundation logic for stitching and export.
  - `EACRenderer.swift`: Metal host logic.
  - `Shaders/EACShader.metal`: Compute shader for 360 projection.
  - `GPMFParser.swift`: GoPro Metadata track parser.
  - `TrackMapOverlay.swift`: GPS path rendering.
- `Package.swift`: Swift Package Manager configuration.
- `Makefile`: Terminal-based build commands.

---
Created by Antigravity for high-performance GoPro workflows.
