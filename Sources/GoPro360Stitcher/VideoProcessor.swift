import Foundation
import SwiftUI
import AVFoundation
import CoreLocation

@MainActor
class VideoProcessor: ObservableObject {
    @Published var composition: AVMutableComposition?
    @Published var player: AVPlayer?
    @Published var videoComposition: AVMutableVideoComposition?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // Extracted metadata
    @Published var extractedTelemetry: [CLLocationCoordinate2D] = []
    
    func processFiles(urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }
        
        print("📽 [Processor] Starting ingestion of \(urls.count) items...")
        
        // 1. Handle security scoping for Mac URLs
        let scopedUrls = urls.compactMap { url -> URL? in
            if url.startAccessingSecurityScopedResource() {
                return url
            }
            // If it's not a security scoped resource (e.g. local dev file), just return it
            return url
        }
        
        do {
            // 2. Filter out .LRV, .THM and keep only .360 files
            let videoUrls = scopedUrls.filter { $0.pathExtension.lowercased() == "360" }
            print("📽 [Processor] Found \(videoUrls.count) valid .360 files.")
            guard !videoUrls.isEmpty else { 
                print("⚠️ [Processor] No .360 files found. Aborting.")
                return 
            }
            
            // 3. Sort by creation date
            print("📽 [Processor] Sorting chapters by creation date...")
            let sortedUrls = try sortFilesByCreationDate(urls: videoUrls)
            for (idx, url) in sortedUrls.enumerated() {
                print("   [\(idx)] \(url.lastPathComponent)")
            }
            
            // 4. Setup virtual stitching via AVMutableComposition
            print("📽 [Processor] Initializing virtual stitching...")
            try await stitchFiles(urls: sortedUrls)
            print("✅ [Processor] Virtual timeline ready.")
            
        } catch {
            self.error = error
            print("❌ [Processor] Error processing files: \(error.localizedDescription)")
        }
        
        // Release security scoping later if needed, but for AVAsset it's safer to keep active during processing
    }
    
    private func sortFilesByCreationDate(urls: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        let sorted = try urls.sorted { url1, url2 in
            let attributes1 = try fileManager.attributesOfItem(atPath: url1.path)
            let attributes2 = try fileManager.attributesOfItem(atPath: url2.path)
            
            let date1 = attributes1[.creationDate] as? Date ?? Date.distantPast
            let date2 = attributes2[.creationDate] as? Date ?? Date.distantPast
            
            // Fallback to filename sorting if dates are identical
            if date1 == date2 {
                return url1.lastPathComponent < url2.lastPathComponent
            }
            return date1 < date2
        }
        return sorted
    }
    
    private func stitchFiles(urls: [URL]) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return
        }
        
        var currentTime = CMTime.zero
        
        for url in urls {
            print("📽 [Stitcher] Processing chapter: \(url.lastPathComponent)")
            let asset = AVURLAsset(url: url)
            
            // We use Swift Concurrency to load tracks
            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
                  let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                print("❌ [Stitcher] Failed to load tracks for \(url.lastPathComponent)")
                continue
            }
            
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            
            try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: currentTime)
            try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
            
            print("📽 [Stitcher]   - Appended \(String(format: "%.2f", duration.seconds))s at \(String(format: "%.2f", currentTime.seconds))s")
            
            // Accumulate duration for next chapter
            currentTime = CMTimeAdd(currentTime, duration)
        }
        
        // Save the composed virtual timeline
        self.composition = composition
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        print("✅ [Stitcher] Composition complete. Total duration: \(String(format: "%.2f", currentTime.seconds))s")
    }
    
    func generateVideoComposition() -> AVVideoComposition? {
        guard let composition = composition else { return nil }
        
        return AVMutableVideoComposition(asset: composition) { request in
            let sourceImage = request.sourceImage
            // Note: In a real implementation we would use the EACRenderer here.
            request.finish(with: sourceImage, context: nil)
        }
    }
    
    func exportVideo(to outputUrl: URL) async throws {
        guard let composition = composition else { return }
        print("🚀 [Exporter] Starting export to \(outputUrl.path)...")
        
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exporter?.videoComposition = generateVideoComposition()
        exporter?.outputURL = outputUrl
        exporter?.outputFileType = AVFileType.mp4
        
        print("🚀 [Exporter] M4 Media Engine Warming Up...")
        await exporter?.export()
        
        if exporter?.status == .failed {
            let err = exporter?.error ?? NSError(domain: "ExportError", code: -1)
            print("❌ [Exporter] Export failed: \(err.localizedDescription)")
            throw err
        }
        
        print("✅ [Exporter] Export successful!")
    }
}
