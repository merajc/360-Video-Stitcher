import Foundation
import SwiftUI
import AVFoundation
import CoreLocation
import VideoToolbox
import CoreImage

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

final class UnsafeImageContainer: @unchecked Sendable {
    var image: CGImage?
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
    @Published var isPlaying: Bool = false
    
    @Published var exportResolution: ExportResolution = .uhd4k
    @Published var exportCodec: ExportCodec = .hevc
    @Published var exportBitrate: ExportBitrate = .high
    @Published var exportSpatialAudio: Bool = true
    
    // Telemetry display states
    @Published var showTrackMap = true
    @Published var showTelemetryDashboard = true
    @Published var showSpeedGauge = true
    @Published var showAltitudeGauge = true
    @Published var showGForceGauge = true
    @Published var telemetryScale: Double = UserDefaults.standard.object(forKey: "telemetryScale") as? Double ?? 1.0 { didSet { UserDefaults.standard.set(telemetryScale, forKey: "telemetryScale") } }
    
    /// Remember loaded file URLs so we can reload when toggling audio tracks or closing/reopening
    private(set) var loadedURLs: [URL] = []
    
    // Reframing Parameters - Top View
    @Published var topPan: Double = UserDefaults.standard.object(forKey: "topPan") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(topPan, forKey: "topPan") } }
    @Published var topTilt: Double = UserDefaults.standard.object(forKey: "topTilt") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(topTilt, forKey: "topTilt") } }
    @Published var topRoll: Double = UserDefaults.standard.object(forKey: "topRoll") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(topRoll, forKey: "topRoll") } }
    @Published var topFOV: Double = UserDefaults.standard.object(forKey: "topFOV") as? Double ?? 90 { didSet { updateVideoComposition(); UserDefaults.standard.set(topFOV, forKey: "topFOV") } }
    @Published var topFlipH: Bool = UserDefaults.standard.bool(forKey: "topFlipH") { didSet { updateVideoComposition(); UserDefaults.standard.set(topFlipH, forKey: "topFlipH") } }
    @Published var topFlipV: Bool = UserDefaults.standard.bool(forKey: "topFlipV") { didSet { updateVideoComposition(); UserDefaults.standard.set(topFlipV, forKey: "topFlipV") } }
    
    // Reframing Parameters - Bottom View
    @Published var bottomPan: Double = UserDefaults.standard.object(forKey: "bottomPan") as? Double ?? 180 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomPan, forKey: "bottomPan") } }
    @Published var bottomTilt: Double = UserDefaults.standard.object(forKey: "bottomTilt") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomTilt, forKey: "bottomTilt") } }
    @Published var bottomRoll: Double = UserDefaults.standard.object(forKey: "bottomRoll") as? Double ?? 0 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomRoll, forKey: "bottomRoll") } }
    @Published var bottomFOV: Double = UserDefaults.standard.object(forKey: "bottomFOV") as? Double ?? 90 { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomFOV, forKey: "bottomFOV") } }
    @Published var bottomFlipH: Bool = UserDefaults.standard.bool(forKey: "bottomFlipH") { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomFlipH, forKey: "bottomFlipH") } }
    @Published var bottomFlipV: Bool = UserDefaults.standard.bool(forKey: "bottomFlipV") { didSet { updateVideoComposition(); UserDefaults.standard.set(bottomFlipV, forKey: "bottomFlipV") } }
    
    // Batch queue
    @Published var batchQueue: [ExportJob] = []
    @Published var batchActiveJobName: String?
    
    // Extracted metadata
    @Published var extractedTelemetry: [CLLocationCoordinate2D] = []
    
    func processFiles(urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }
        
        // Store URLs for reloading
        self.loadedURLs = urls
        
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
            
            // 5. Extract GPS Telemetry from ALL chapters
            let parser = GPMFParser()
            var allPoints: [GPSData] = []
            var timeOffset: Double = 0.0
            
            for url in sortedUrls {
                print("📽 [Processor] Extracting telemetry from \(url.lastPathComponent)...")
                let chapterPoints = await parser.extractGPSData(from: url)
                
                // Offset timestamps so they're continuous across the stitched composition
                let offsetPoints = chapterPoints.map { point in
                    var offsetPoint = GPSData(
                        timestamp: CMTimeAdd(point.timestamp, CMTime(seconds: timeOffset, preferredTimescale: 600)),
                        coordinate: point.coordinate,
                        altitude: point.altitude,
                        speed: point.speed,
                        speed3D: point.speed3D
                    )
                    offsetPoint.accelX = point.accelX
                    offsetPoint.accelY = point.accelY
                    offsetPoint.accelZ = point.accelZ
                    return offsetPoint
                }
                allPoints.append(contentsOf: offsetPoints)
                
                // Use actual video duration for time offset (matches composition timeline)
                let tempDir = FileManager.default.temporaryDirectory
                let tempUrl = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                try? FileManager.default.createSymbolicLink(at: tempUrl, withDestinationURL: url)
                let asset = AVURLAsset(url: FileManager.default.fileExists(atPath: tempUrl.path) ? tempUrl : url)
                let duration = try await asset.load(.duration)
                timeOffset += duration.seconds
                try? FileManager.default.removeItem(at: tempUrl)
                
                print("   ↳ \(chapterPoints.count) points (cumulative offset: \(String(format: "%.1f", timeOffset))s)")
            }
            
            // Ensure all points are strictly sorted chronologically across chapters
            allPoints.sort { $0.timestamp.seconds < $1.timestamp.seconds }
            
            self.telemetry.loadTelemetry(allPoints)
            self.extractedTelemetry = allPoints.map { $0.coordinate }
            print("✅ [Processor] Total telemetry: \(allPoints.count) GPS points across \(sortedUrls.count) chapters.")
            
            print("✅ [Processor] Virtual timeline ready.")
            
        } catch {
            self.error = error
            print("❌ [Processor] Error processing files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Playback Controls
    
    func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    func closeFile() {
        player?.pause()
        player = nil
        composition = nil
        videoComposition = nil
        isPlaying = false
        loadedURLs = []
        telemetry.trackPoints = []
        extractedTelemetry = []
        batchQueue = []
        error = nil
        exportProgress = 0.0
        print("📁 [Processor] File closed. Ready for new files.")
    }
    
    /// Reload the composition with the current spatial audio setting, preserving playback position
    func reloadAudioTrack() async {
        guard !loadedURLs.isEmpty else { return }
        let savedTime = player?.currentTime() ?? .zero
        let wasPlaying = isPlaying
        
        player?.pause()
        isPlaying = false
        
        await processFiles(urls: loadedURLs)
        
        // Restore playback position
        if let player = player {
            await player.seek(to: savedTime, toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlaying {
                player.play()
                isPlaying = true
            }
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
                
                guard videoTracks.count >= 2 else {
                    print("❌ [Stitcher] Missing dual-video tracks in \(url.lastPathComponent).")
                    continue
                }
                
                var selectedAudioTrack: AVAssetTrack?
                if exportSpatialAudio {
                    for track in audioTracks {
                        if let formatDescs = try? await track.load(.formatDescriptions),
                           let formatDesc = formatDescs.first,
                           let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                            if streamDesc.pointee.mChannelsPerFrame == 4 {
                                selectedAudioTrack = track
                                print("📽 [Stitcher]   - Selected 4-Channel Ambisonics Audio Track.")
                                break
                            }
                        }
                    }
                }
                
                if selectedAudioTrack == nil {
                    selectedAudioTrack = audioTracks.first
                    if let _ = selectedAudioTrack {
                        print("📽 [Stitcher]   - Selected Default/Stereo Audio Track.")
                    }
                }
                
                guard let assetAudioTrack = selectedAudioTrack else {
                    print("❌ [Stitcher] Missing audio track in \(url.lastPathComponent).")
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
        instruction.topFlipH = topFlipH
        instruction.topFlipV = topFlipV
        
        instruction.bottomPan = Float(bottomPan)
        instruction.bottomTilt = Float(bottomTilt)
        instruction.bottomRoll = Float(bottomRoll)
        instruction.bottomFOV = Float(bottomFOV)
        instruction.bottomFlipH = bottomFlipH
        instruction.bottomFlipV = bottomFlipV
        
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
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(job.resolution.size.width),
                kCVPixelBufferHeightKey as String: Int(job.resolution.size.height)
            ]
        )
        
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
            
            // Check if we have 4 channels in the composition (Spatial Audio)
            var has4ChannelAudio = false
            for track in audioTracks {
                if let formatDescs = try? await track.load(.formatDescriptions),
                   let formatDesc = formatDescs.first,
                   let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                    if streamDesc.pointee.mChannelsPerFrame == 4 {
                        has4ChannelAudio = true
                        break
                    }
                }
            }
            
            if has4ChannelAudio {
                var channelLayout = AudioChannelLayout()
                channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Ambisonic_B_Format
                let layoutData = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
                
                audioSettings[AVNumberOfChannelsKey] = 4
                audioSettings[AVChannelLayoutKey] = layoutData
                print("🔈 [Exporter] Configured 4-Channel Ambisonics audio output.")
            } else {
                print("🔈 [Exporter] Configured 2-Channel Stereo audio output.")
            }
            
            if job.codec == .prores {
                // ProRes typical audio is LPCM
                audioSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: has4ChannelAudio ? 4 : 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                
                if has4ChannelAudio {
                    var channelLayout = AudioChannelLayout()
                    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Ambisonic_B_Format
                    let layoutData = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
                    audioSettings[AVChannelLayoutKey] = layoutData
                }
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
        
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        nonisolated(unsafe) let safePixelBufferAdaptor = pixelBufferAdaptor
        let localShowTrackMap = self.showTrackMap
        let localShowDashboard = self.showTelemetryDashboard
        let localShowSpeed = self.showSpeedGauge
        let localShowAlt = self.showAltitudeGauge
        let localShowGForce = self.showGForceGauge
        let localScale = self.telemetryScale
        let localRes = job.resolution.size
        
        safeVideoInput.requestMediaDataWhenReady(on: videoQueue) {
            while safeVideoInput.isReadyForMoreMediaData {
                if let sampleBuffer = safeVideoOutput.copyNextSampleBuffer() {
                    let pTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let pTimeSeconds = pTime.seconds
                    
                    var appended = false
                    
                    if localShowTrackMap || localShowDashboard {
                        if let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            let imageContainer = UnsafeImageContainer()
                            
                            let semaphore = DispatchSemaphore(value: 0)
                            Task { @MainActor in
                                self.telemetry.updateCurrentTime(pTimeSeconds)
                                let overlayView = ExportOverlayView(
                                    telemetry: self.telemetry,
                                    currentTime: pTimeSeconds,
                                    size: localRes,
                                    showTrackMap: localShowTrackMap,
                                    showDashboard: localShowDashboard,
                                    showSpeed: localShowSpeed,
                                    showAltitude: localShowAlt,
                                    showGForce: localShowGForce,
                                    scale: localScale
                                )
                                let renderer = ImageRenderer(content: overlayView)
                                renderer.scale = 1.0
                                renderer.proposedSize = .init(width: localRes.width, height: localRes.height)
                                imageContainer.image = renderer.cgImage
                                semaphore.signal()
                            }
                            semaphore.wait()
                            
                            if let overlayCGImage = imageContainer.image, let pool = safePixelBufferAdaptor.pixelBufferPool {
                                var newPixelBuffer: CVPixelBuffer?
                                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &newPixelBuffer)
                                if let newPixelBuffer = newPixelBuffer {
                                    let bgImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
                                    
                                    // CIImage from CGImage correctly aligns with CVPixelBuffer automatically.
                                    let fgImage = CIImage(cgImage: overlayCGImage)
                                    
                                    let composite = fgImage.composited(over: bgImage)
                                    ciContext.render(composite, to: newPixelBuffer)
                                    
                                    safePixelBufferAdaptor.append(newPixelBuffer, withPresentationTime: pTime)
                                    appended = true
                                }
                            }
                        }
                    }
                    
                    if !appended {
                        safeVideoInput.append(sampleBuffer)
                    }
                    
                    DispatchQueue.main.async {
                        self.exportProgress = pTimeSeconds / durationSeconds
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
