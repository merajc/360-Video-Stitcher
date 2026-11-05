import SwiftUI
import AVFoundation

@main
struct GoPro360StitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("GoPro 360 Stitcher") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        guard let testIndex = args.firstIndex(of: "--test-file"), testIndex + 1 < args.count else {
            return
        }
        
        let inputURL = URL(fileURLWithPath: args[testIndex + 1])
        let durationSeconds = args.firstIndex(of: "--test-duration").flatMap { Int(args[$0 + 1]) } ?? 0
        let outputPath = Self.resolveOutputPath(args: args, inputURL: inputURL)
        
        try? FileManager.default.createDirectory(
            at: outputPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: outputPath)
        
        print("🧪 [TestMode] Starting end-to-end test for: \(inputURL.path)")
        print("🧪 [TestMode] Output: \(outputPath.path)")
        if durationSeconds > 0 {
            print("🧪 [TestMode] Limit: \(durationSeconds) seconds")
        }
        
        Task {
            let processor = VideoProcessor()
            
            await processor.processFiles(urls: [inputURL])
            
            guard processor.composition != nil else {
                print("❌ [TestMode] File processing failed (composition is nil).")
                exit(1)
            }
            
            print("🧪 [TestMode] File processed successfully. Exporting...")
            do {
                let maxDuration = durationSeconds > 0
                    ? CMTime(seconds: Double(durationSeconds), preferredTimescale: 600)
                    : nil
                processor.addToQueue(name: "Test Job", outputUrl: outputPath)
                
                guard let job = processor.batchQueue.first else {
                    print("❌ [TestMode] Could not enqueue the export job.")
                    exit(1)
                }
                
                try await processor.exportVideoWithWriter(job: job, maxDuration: maxDuration)
                print("🧪 [TestMode] Export finished at: \(outputPath.path)")
                print("✅ [TestMode] TEST PASSED!")
                NSApplication.shared.terminate(nil)
            } catch {
                print("❌ [TestMode] Export failed: \(error.localizedDescription)")
                exit(1)
            }
        }
    }
    
    /// `--output <path>` wins. Otherwise the file is written next to the source clip,
    /// falling back to ~/Movies when that location is read-only (e.g. an SD card).
    private static func resolveOutputPath(args: [String], inputURL: URL) -> URL {
        if let index = args.firstIndex(of: "--output"), index + 1 < args.count {
            return URL(fileURLWithPath: args[index + 1])
        }
        
        let fileName = inputURL.deletingPathExtension().lastPathComponent + "_stitched"
        let directory = inputURL.deletingLastPathComponent()
        
        if FileManager.default.isWritableFile(atPath: directory.path) {
            return directory.appendingPathComponent(fileName).appendingPathExtension("mp4")
        }
        
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies")
            .appendingPathComponent(fileName)
            .appendingPathExtension("mp4")
    }
    
    // Enable closing the last window to quit the app, to avoid ghost background processes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
