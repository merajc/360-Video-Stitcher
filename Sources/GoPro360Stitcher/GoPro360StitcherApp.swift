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
        if let testIndex = args.firstIndex(of: "--test-file"), testIndex + 1 < args.count {
            let path = args[testIndex + 1]
            let durationSeconds = args.firstIndex(of: "--test-duration").flatMap { Int(args[$0 + 1]) } ?? 0
            
            let outputDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            let outputPath = outputDir.appendingPathComponent("Ferrari_10s_Test.mp4")
            try? FileManager.default.removeItem(at: outputPath)
            
            print("🧪 [TestMode] Starting end-to-end test for: \(path)")
            if durationSeconds > 0 {
                print("🧪 [TestMode] Limit: \(durationSeconds) seconds")
            }
            
            Task {
                let processor = await VideoProcessor()
                let url = URL(fileURLWithPath: path)
                
                await processor.processFiles(urls: [url])
                
                if await processor.composition != nil {
                    print("🧪 [TestMode] File processed successfully. Exporting...")
                    do {
                        let maxDuration = durationSeconds > 0 ? CMTime(seconds: Double(durationSeconds), preferredTimescale: 600) : nil
                        await processor.addToQueue(name: "Test Job", outputUrl: outputPath)
                        if let job = await processor.batchQueue.first {
                            try await processor.exportVideoWithWriter(job: job, maxDuration: maxDuration)
                        }
                        print("🧪 [TestMode] Export finished at: \(outputPath.path)")
                        print("✅ [TestMode] TEST PASSED!")
                        await NSApplication.shared.terminate(nil)
                    } catch {
                        print("❌ [TestMode] Export failed: \(error.localizedDescription)")
                        exit(1)
                    }
                } else {
                    print("❌ [TestMode] File processing failed (composition is nil).")
                    exit(1)
                }
            }
        }
    }
    
    // Enable closing the last window to quit the app, to avoid ghost background processes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
