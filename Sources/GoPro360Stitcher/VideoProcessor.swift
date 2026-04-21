import Foundation
import SwiftUI
import AVFoundation
import CoreLocation

@MainActor
class VideoProcessor: ObservableObject {
    @Published var composition: AVMutableComposition?
    @Published var player: AVPlayer?
    let telemetry = TelemetryProcessor()
    @Published var videoComposition: AVMutableVideoComposition?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var exportProgress: Double = 0.0
    @Published var isExporting: Bool = false
    
    // Reframing Parameters - Top View
    @Published var topPan: Double = 0 { didSet { updateVideoComposition() } }
    @Published var topTilt: Double = 0 { didSet { updateVideoComposition() } }
    @Published var topRoll: Double = 0 { didSet { updateVideoComposition() } }
    @Published var topFOV: Double = 90 { didSet { updateVideoComposition() } }
    
    // Reframing Parameters - Bottom View
    @Published var bottomPan: Double = 180 { didSet { updateVideoComposition() } }
    @Published var bottomTilt: Double = 0 { didSet { updateVideoComposition() } }
    @Published var bottomRoll: Double = 0 { didSet { updateVideoComposition() } }
    @Published var bottomFOV: Double = 90 { didSet { updateVideoComposition() } }
    
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
            
            // 5. Extract GPS Telemetry
            if let firstUrl = sortedUrls.first {
                print("📽 [Processor] Extracting telemetry from \(firstUrl.lastPathComponent)...")
                let parser = GPMFParser()
                let points = await parser.extractGPSData(from: firstUrl)
                self.extractedTelemetry = points.map { $0.coordinate }
                print("✅ [Processor] Extracted \(points.count) GPS points.")
            }
            
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
        guard let videoTrackFront = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoTrackRear = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return
        }
        
        var currentTime = CMTime.zero
        
        for url in urls {
            print("📽 [Stitcher] Processing chapter: \(url.path)")
            
            // WORKAROUND: AVFoundation does not natively recognize .360 extension.
            let tempDir = FileManager.default.temporaryDirectory
            let tempUrl = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            
            print("📽 [Stitcher]   - Creating symlink: \(tempUrl.path)")
            do {
                try FileManager.default.createSymbolicLink(at: tempUrl, withDestinationURL: url)
            } catch {
                print("⚠️ [Stitcher] Failed to create symlink: \(error.localizedDescription)")
            }
            
            let assetUrl = FileManager.default.fileExists(atPath: tempUrl.path) ? tempUrl : url
            if assetUrl == url {
                print("⚠️ [Stitcher]   - Symlink check failed, using original URL.")
            } else {
                print("📽 [Stitcher]   - Symlink confirmed at: \(assetUrl.path)")
            }
            
            let asset = AVURLAsset(url: assetUrl)
            
            defer {
                if assetUrl != url {
                    try? FileManager.default.removeItem(at: assetUrl)
                    print("📽 [Stitcher]   - Cleaned up symlink.")
                }
            }
            
            print("📽 [Stitcher]   - Loading tracks...")
            do {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                
                print("📽 [Stitcher]   - Found \(videoTracks.count) video tracks and \(audioTracks.count) audio tracks.")
                
                guard videoTracks.count >= 2, let assetAudioTrack = audioTracks.first else {
                    print("❌ [Stitcher] Missing dual-video tracks in \(url.lastPathComponent).")
                    continue
                }
                
                let assetVideoTrackFront = videoTracks[0]
                let assetVideoTrackRear = videoTracks[1]
                
                let duration = try await asset.load(.duration)
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                
                try videoTrackFront.insertTimeRange(timeRange, of: assetVideoTrackFront, at: currentTime)
                try videoTrackRear.insertTimeRange(timeRange, of: assetVideoTrackRear, at: currentTime)
                try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
                
                print("📽 [Stitcher]   - Appended \(String(format: "%.2f", duration.seconds))s Dual-Video at \(String(format: "%.2f", currentTime.seconds))s")
                
                currentTime = CMTimeAdd(currentTime, duration)
            } catch {
                print("❌ [Stitcher] Load failed for \(url.lastPathComponent): \(error.localizedDescription)")
                if let nsErr = error as NSError? {
                    print("   Debug: Domain=\(nsErr.domain) Code=\(nsErr.code) UserInfo=\(nsErr.userInfo)")
                }
                throw error
            }
        }
        
        self.composition = composition
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = generateVideoComposition()
        self.player = AVPlayer(playerItem: item)
        print("✅ [Stitcher] Composition complete. Total duration: \(String(format: "%.2f", currentTime.seconds))s")
        
        Task {
            await telemetry.extractTelemetry(from: composition)
        }
    }
    
    private let renderer = EACRenderer()
    
    func generateVideoComposition() -> AVVideoComposition? {
        guard let composition = composition else { return nil }
        
        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            request.finish(with: request.sourceImage, context: nil)
        }
        
        videoComposition.customVideoCompositorClass = EACCompositor.self
        videoComposition.renderSize = CGSize(width: 1080, height: 1920)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        let trackIDs = composition.tracks(withMediaType: .video).map { NSNumber(value: $0.trackID) }
        
        let instruction = EACInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            sourceTrackIDs: trackIDs
        )
        
        instruction.topPan = Float(topPan)
        instruction.topTilt = Float(topTilt)
        instruction.topRoll = Float(topRoll)
        instruction.topFOV = Float(topFOV)
        
        instruction.bottomPan = Float(bottomPan)
        instruction.bottomTilt = Float(bottomTilt)
        instruction.bottomRoll = Float(bottomRoll)
        instruction.bottomFOV = Float(bottomFOV)
        
        videoComposition.instructions = [instruction]
        return videoComposition
    }
    
    private func updateVideoComposition() {
        guard let player = player, let item = player.currentItem else { return }
        item.videoComposition = generateVideoComposition()
    }
    
    func exportVideo(to outputUrl: URL, maxDuration: CMTime? = nil) async throws {
        guard let composition = composition else {
            print("⚠️ [Exporter] No composition found to export.")
            return
        }
        
        isExporting = true
        exportProgress = 0.0
        defer { isExporting = false }
        
        print("🚀 [Exporter] Starting export to \(outputUrl.path)...")
        if let maxDuration = maxDuration {
            print("🚀 [Exporter] Limiting export duration to \(String(format: "%.2f", maxDuration.seconds))s")
        }
        
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        let videoComp = generateVideoComposition()
        
        if let maxDuration = maxDuration {
            exporter?.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(maxDuration, composition.duration))
        }
        
        exporter?.videoComposition = videoComp
        exporter?.outputURL = outputUrl
        exporter?.outputFileType = AVFileType.mp4
        
        guard let exporter = exporter else {
            print("❌ [Exporter] Failed to initialize AVAssetExportSession.")
            return
        }
        
        print("🚀 [Exporter] M4 Media Engine Warming Up...")
        
        // Progress tracking task
        let progressTask = Task {
            while exporter.status == .waiting || exporter.status == .exporting {
                let progress = Double(exporter.progress)
                await MainActor.run {
                    self.exportProgress = progress
                }
                
                // Terminal progress bar
                let barWidth = 20
                let filled = Int(progress * Double(barWidth))
                let empty = barWidth - filled
                let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
                print("\r🚀 [Exporter] Progress: [\(bar)] \(Int(progress * 100))%", terminator: "")
                fflush(stdout)
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            print("\n") // New line after progress bar
        }
        
        await exporter.export()
        progressTask.cancel()
        
        if exporter.status == .failed {
            let err = exporter.error ?? NSError(domain: "ExportError", code: -1)
            print("❌ [Exporter] Export failed: \(err.localizedDescription)")
            if let underlyingError = (err as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
                print("   Debug: \(underlyingError.localizedDescription)")
            }
            throw err
        } else if exporter.status == .cancelled {
            print("⚠️ [Exporter] Export cancelled.")
        } else {
            print("✅ [Exporter] Export successful! Saved to: \(outputUrl.path)")
            self.exportProgress = 1.0
        }
    }
}
