import Foundation
import SwiftUI
import AVFoundation
import CoreLocation
import VideoToolbox

enum ExportResolution: String, CaseIterable, Identifiable {
    case hd1080 = "1080p (HD)"
    case uhd4k = "4K (UHD)"
    case max5_6k = "5.6K (MAX)"
    
    var id: String { rawValue }
    
    var size: CGSize {
        switch self {
        case .hd1080: return CGSize(width: 1080, height: 1920)
        case .uhd4k: return CGSize(width: 2160, height: 3840)
        case .max5_6k: return CGSize(width: 3168, height: 5632)
        }
    }
}

enum ExportCodec: String, CaseIterable, Identifiable {
    case hevc = "HEVC (H.265)"
    case prores = "Apple ProRes 422"
    
    var id: String { rawValue }
    
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .prores: return .proRes422
        }
    }
}

enum ExportBitrate: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case high = "High"
    case maximum = "Maximum"
    
    var id: String { rawValue }
    
    func bitsPerSecond(for resolution: ExportResolution) -> Int {
        let baseMultiplier: Double
        switch self {
        case .standard: baseMultiplier = 1.0
        case .high: baseMultiplier = 2.0
        case .maximum: baseMultiplier = 4.0
        }
        
        switch resolution {
        case .hd1080: return Int(15_000_000 * baseMultiplier)
        case .uhd4k: return Int(40_000_000 * baseMultiplier)
        case .max5_6k: return Int(80_000_000 * baseMultiplier)
        }
    }
}

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
    
    @Published var exportResolution: ExportResolution = .uhd4k
    @Published var exportCodec: ExportCodec = .hevc
    @Published var exportBitrate: ExportBitrate = .high
    
    // Reframing Parameters - Top View
    @Published var topPan: Double = UserDefaults.standard.object(forKey: "topPan") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(topPan, forKey: "topPan") } }
    @Published var topTilt: Double = UserDefaults.standard.object(forKey: "topTilt") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(topTilt, forKey: "topTilt") } }
    @Published var topRoll: Double = UserDefaults.standard.object(forKey: "topRoll") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(topRoll, forKey: "topRoll") } }
    @Published var topFOV: Double = UserDefaults.standard.object(forKey: "topFOV") as? Double ?? 90 { didSet { updateVideoComposition(); UserDefaults.standard.set(topFOV, forKey: "topFOV") } }
    
    // Reframing Parameters - Bottom View
    @Published var bottomPan: Double = UserDefaults.standard.object(forKey: "bottomPan") as? Double ?? 180 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomPan, forKey: "bottomPan") } }
    @Published var bottomTilt: Double = UserDefaults.standard.object(forKey: "bottomTilt") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomTilt, forKey: "bottomTilt") } }
    @Published var bottomRoll: Double = UserDefaults.standard.object(forKey: "bottomRoll") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomRoll, forKey: "bottomRoll") } }
    @Published var bottomFOV: Double = UserDefaults.standard.object(forKey: "bottomFOV") as? Double ?? 90 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomFOV, forKey: "bottomFOV") } }
    
    // Batch queue
    @Published var batchQueue: [ExportJob] = []
    @Published var batchActiveJobName: String?
    
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
        videoComposition.renderSize = exportResolution.size
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
    
    func addToQueue(name: String, outputUrl: URL) {
        guard let composition = composition, let videoComp = generateVideoComposition() else {
            return
        }
        
        let job = ExportJob(
            name: name,
            composition: composition,
            videoComposition: videoComp,
            duration: composition.duration,
            outputUrl: outputUrl,
            resolution: exportResolution,
            codec: exportCodec,
            bitrate: exportBitrate
        )
        
        batchQueue.append(job)
    }
    
    func startBatchExport() async {
        guard !isExporting else { return }
        isExporting = true
        defer {
            isExporting = false
            batchActiveJobName = nil
            exportProgress = 0.0
        }
        
        for index in batchQueue.indices {
            let job = batchQueue[index]
            if case .completed = job.status { continue }
            
            DispatchQueue.main.async {
                self.batchQueue[index].status = .exporting
                self.batchActiveJobName = job.name
            }
            
            do {
                try await exportVideoWithWriter(job: job)
                DispatchQueue.main.async {
                    self.batchQueue[index].status = .completed
                    self.batchQueue[index].progress = 1.0
                }
            } catch {
                DispatchQueue.main.async {
                    self.batchQueue[index].status = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    func exportVideoWithWriter(job: ExportJob, maxDuration: CMTime? = nil) async throws {
        print("🚀 [Exporter] Starting AVAssetWriter export to \(job.outputUrl.path)...")
        exportProgress = 0.0
        let totalDuration = maxDuration != nil ? CMTimeMinimum(maxDuration!, job.duration) : job.duration
        
        let reader = try AVAssetReader(asset: job.composition)
        let writer = try AVAssetWriter(outputURL: job.outputUrl, fileType: job.codec == .hevc ? .mp4 : .mov)
        
        // 1. Video Setup
        let videoComp = job.videoComposition
        let videoTracks = job.composition.tracks(withMediaType: .video)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        videoOutput.videoComposition = videoComp
        if reader.canAdd(videoOutput) { reader.add(videoOutput) }
        
        var compressionProps: [String: Any] = [:]
        if job.codec == .hevc {
            compressionProps[AVVideoAverageBitRateKey as String] = job.bitrate.bitsPerSecond(for: job.resolution)
            compressionProps[AVVideoProfileLevelKey as String] = kVTProfileLevel_HEVC_Main_AutoLevel
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: job.codec.avVideoCodecType,
            AVVideoWidthKey: job.resolution.size.width,
            AVVideoHeightKey: job.resolution.size.height,
            AVVideoCompressionPropertiesKey: compressionProps
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        if writer.canAdd(videoInput) { writer.add(videoInput) }
        
        // 2. Audio Setup
        let audioTracks = job.composition.tracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        var audioInput: AVAssetWriterInput?
        
        if !audioTracks.isEmpty {
            audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            if reader.canAdd(audioOutput!) { reader.add(audioOutput!) }
            
            var audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
            
            if job.codec == .prores {
                // ProRes typical audio is LPCM
                audioSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            }
            
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = false
            if writer.canAdd(audioInput!) { writer.add(audioInput!) }
        }
        
        reader.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        
        print("🚀 [Exporter] Starting read/write loop...")
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)
        
        let dispatchGroup = DispatchGroup()
        let videoQueue = DispatchQueue(label: "com.export.video")
        let audioQueue = DispatchQueue(label: "com.export.audio")
        
        var exportError: Error?
        
        nonisolated(unsafe) let safeVideoInput = videoInput
        nonisolated(unsafe) let safeVideoOutput = videoOutput
        let durationSeconds = totalDuration.seconds
        
        dispatchGroup.enter()
        safeVideoInput.requestMediaDataWhenReady(on: videoQueue) {
            while safeVideoInput.isReadyForMoreMediaData {
                if let sampleBuffer = safeVideoOutput.copyNextSampleBuffer() {
                    safeVideoInput.append(sampleBuffer)
                    let pTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    DispatchQueue.main.async {
                        self.exportProgress = pTime.seconds / durationSeconds
                    }
                } else {
                    safeVideoInput.markAsFinished()
                    dispatchGroup.leave()
                    break
                }
            }
        }
        
        if let aInput = audioInput, let aOutput = audioOutput {
            nonisolated(unsafe) let safeAudioInput = aInput
            nonisolated(unsafe) let safeAudioOutput = aOutput
            dispatchGroup.enter()
            safeAudioInput.requestMediaDataWhenReady(on: audioQueue) {
                while safeAudioInput.isReadyForMoreMediaData {
                    if let sampleBuffer = safeAudioOutput.copyNextSampleBuffer() {
                        safeAudioInput.append(sampleBuffer)
                    } else {
                        safeAudioInput.markAsFinished()
                        dispatchGroup.leave()
                        break
                    }
                }
            }
        }
        
        await withCheckedContinuation { continuation in
            dispatchGroup.notify(queue: .main) {
                continuation.resume()
            }
        }
        
        if reader.status == .failed { exportError = reader.error }
        if writer.status == .failed { exportError = writer.error }
        
        if let error = exportError {
            writer.cancelWriting()
            print("❌ [Exporter] Export failed: \(error.localizedDescription)")
            throw error
        }
        
        await writer.finishWriting()
        
        print("✅ [Exporter] Export successful! Saved to: \(job.outputUrl.path)")
        self.exportProgress = 1.0
    }
}
