import Foundation
import Observation
import AVFoundation
import CoreLocation

@Observable
class VideoProcessor {
    var composition: AVMutableComposition?
    var player: AVPlayer?
    var videoComposition: AVMutableVideoComposition?
    var isLoading: Bool = false
    var error: Error?
    
    // Extracted metadata
    var extractedTelemetry: [CLLocationCoordinate2D] = []
    
    func processFiles(urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. Filter out .LRV, .THM and keep only .360 files
            let videoUrls = urls.filter { $0.pathExtension.lowercased() == "360" }
            guard !videoUrls.isEmpty else { return }
            
            // 2. Sort by creation date
            let sortedUrls = try sortFilesByCreationDate(urls: videoUrls)
            
            // 3. Setup virtual stitching via AVMutableComposition
            try await stitchFiles(urls: sortedUrls)
            
        } catch {
            self.error = error
            print("Error processing files: \(error.localizedDescription)")
        }
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
            let asset = AVURLAsset(url: url)
            
            // We use Swift Concurrency to load tracks
            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
                  let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                continue
            }
            
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            
            try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: currentTime)
            try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
            
            // Accumulate duration for next chapter
            currentTime = CMTimeAdd(currentTime, duration)
        }
        
        // Save the composed virtual timeline
        self.composition = composition
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
    }
    
    func generateVideoComposition() -> AVVideoComposition? {
        guard let composition = composition else { return nil }
        
        return AVMutableVideoComposition(asset: composition) { request in
            // This is where we apply the Metal shader to each frame
            // For the 9:16 vertical output, we render Front on top and Rear on bottom
            
            let sourceImage = request.sourceImage
            let outputSize = request.renderSize
            
            // 1. Create destination image
            // 2. Render Top Half (Front projection)
            // 3. Render Bottom Half (Rear projection)
            // 4. Overlay Track Map
            
            // Note: In a real implementation we would use the EACRenderer here.
            // For now, we return the source to allow the app to compile.
            request.finish(with: sourceImage, context: nil)
        }
    }
    
    func exportVideo(to outputUrl: URL) async throws {
        guard let composition = composition else { return }
        
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exporter?.videoComposition = generateVideoComposition()
        exporter?.outputURL = outputUrl
        exporter?.outputFileType = .mp4
        
        await exporter?.export()
        
        if exporter?.status == .failed {
            throw exporter?.error ?? NSError(domain: "ExportError", code: -1)
        }
    }
}
