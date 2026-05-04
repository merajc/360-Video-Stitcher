import Foundation
import AVFoundation

@MainActor
func runExportTest() async {
    let sourceFile = "/Users/merajchhaya/Pictures/Ferrari track day March 2026/GS020009.360"
    let outputFile = "/Users/merajchhaya/.gemini/antigravity/brain/00777a51-ec45-4183-8889-7553ad66b21a/artifacts/ExportTest_Ferrari.mp4"
    
    print("🎬 [Test] Loading source: \(sourceFile)")
    let url = URL(fileURLWithPath: sourceFile)
    
    let processor = VideoProcessor()
    
    // We need to simulate the file loading
    await processor.processFiles(urls: [url])
    
    // Set some interesting dual-view parameters
    // Top view: Facing forward (Track)
    processor.topPan = 0
    processor.topTilt = 0
    processor.topFOV = 100
    
    // Bottom view: Facing driver
    processor.bottomPan = 180
    processor.bottomTilt = 10
    processor.bottomFOV = 110
    
    print("🎬 [Test] Starting 10-second export...")
    let outputUrl = URL(fileURLWithPath: outputFile)
    
    // Ensure parent dir exists
    try? FileManager.default.createDirectory(at: outputUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
    
    do {
        processor.addToQueue(name: "Test Job", outputUrl: outputUrl)
        if let job = processor.batchQueue.first {
            try await processor.exportVideoWithWriter(job: job, maxDuration: CMTime(seconds: 10, preferredTimescale: 600))
            print("✅ [Test] Export successful! Saved to: \(outputFile)")
        }
    } catch {
        print("❌ [Test] Export failed: \(error.localizedDescription)")
    }
}

// To run this, I'll need to call it from a Swift script or integrate it into the app entry point temporarily.
// I'll create a main.swift for the executable to run this if requested.
// But first, let's fix the VideoProcessor.exportVideo method to correctly wait for completion.
