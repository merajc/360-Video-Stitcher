import AVFoundation
import CoreImage
import SwiftUI

/// One-shot flag that makes a `DispatchGroup.leave()` safe to attempt from several
/// exit paths (end of stream, write failure, cancellation).
final class ExportOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    /// Returns `true` the first time it is called, `false` afterwards.
    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Cancellation flag shared between the UI and the export pump queues.
final class ExportCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func clear() {
        lock.lock()
        value = false
        lock.unlock()
    }
}

/// Thread-safe error slot for failures raised on the pump queues.
final class ExportErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ error: Error) {
        lock.lock()
        if stored == nil { stored = error }
        lock.unlock()
    }
}

enum ExportStreamError {
    static func videoFrame(time: Double) -> NSError {
        NSError(
            domain: "360VideoStitcher",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "The video encoder stopped accepting frames at \(String(format: "%.2f", time))s. The export was stopped to avoid a truncated file."]
        )
    }

    static let audio = NSError(
        domain: "360VideoStitcher",
        code: -4,
        userInfo: [NSLocalizedDescriptionKey: "The audio encoder stopped accepting samples. The export was stopped to avoid a truncated file."]
    )

    static let cancelled = NSError(
        domain: "360VideoStitcher",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Export cancelled."]
    )
}

@MainActor
extension VideoProcessor {
    /// Streams the composition through the reader/writer pair, optionally compositing
    /// telemetry overlays, and always resolves — whether the frames run out, the
    /// encoder fails, or the user cancels.
    func runExportStreams(
        job: ExportJob,
        writer: AVAssetWriter,
        reader: AVAssetReader,
        videoInput: AVAssetWriterInput,
        videoOutput: AVAssetReaderVideoCompositionOutput,
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        audioInput: AVAssetWriterInput?,
        audioOutput: AVAssetReaderAudioMixOutput?,
        totalDuration: CMTime
    ) async throws {
        activeWriter = writer
        defer {
            activeWriter = nil
            isCancellingExport = false
        }

        let dispatchGroup = DispatchGroup()
        let videoQueue = DispatchQueue(label: "com.export.video")
        let audioQueue = DispatchQueue(label: "com.export.audio")

        let errorBox = ExportErrorBox()
        let cancelFlag = exportCancelFlag
        let videoFinished = ExportOnce()
        let audioFinished = ExportOnce()
        let ciContext = CIContext(options: [.cacheIntermediates: false])

        // Snapshot the overlay configuration so the pump never touches view state.
        nonisolated(unsafe) let localTelemetry = self.telemetry
        let localShowTrackMap = self.showTrackMap
        let localShowDashboard = self.showTelemetryDashboard
        let localShowSpeed = self.showSpeedGauge
        let localShowAltitude = self.showAltitudeGauge
        let localShowGForce = self.showGForceGauge
        let localScale = self.telemetryScale
        let localResolution = job.resolution.size
        let overlayEnabled = localShowTrackMap || localShowDashboard
        let durationSeconds = max(totalDuration.seconds, 0.001)

        nonisolated(unsafe) let safeVideoInput = videoInput
        nonisolated(unsafe) let safeVideoOutput = videoOutput
        nonisolated(unsafe) let safeAdaptor = pixelBufferAdaptor
        nonisolated(unsafe) let safeWriter = writer

        Log.debug("Export starting: \(job.resolution.rawValue), \(job.codec.rawValue), overlays=\(overlayEnabled), telemetry points=\(localTelemetry.trackPoints.count)")

        // MARK: Video pump

        dispatchGroup.enter()
        safeVideoInput.requestMediaDataWhenReady(on: videoQueue) {
            var lastLoggedPercentage = -1

            while safeVideoInput.isReadyForMoreMediaData && !cancelFlag.isSet && errorBox.error == nil {
                var stop = false

                autoreleasepool {
                    guard let sampleBuffer = safeVideoOutput.copyNextSampleBuffer() else {
                        // End of video: release the group exactly once.
                        if videoFinished.fire() {
                            safeVideoInput.markAsFinished()
                            dispatchGroup.leave()
                        }
                        stop = true
                        return
                    }

                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let seconds = presentationTime.seconds
                    var appended = false

                    if overlayEnabled, let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        let snapshot = localTelemetry.snapshot(at: seconds)
                        var overlayImage: CGImage?

                        // ImageRenderer must run on the main thread.
                        DispatchQueue.main.sync {
                            let overlayView = ExportOverlaySnapshotView(
                                snapshot: snapshot,
                                size: localResolution,
                                showTrackMap: localShowTrackMap,
                                showDashboard: localShowDashboard,
                                showSpeed: localShowSpeed,
                                showAltitude: localShowAltitude,
                                showGForce: localShowGForce,
                                scale: localScale
                            )
                            let renderer = ImageRenderer(content: overlayView)
                            renderer.scale = 1.0
                            renderer.proposedSize = .init(width: localResolution.width, height: localResolution.height)
                            overlayImage = renderer.cgImage
                        }

                        if let overlayImage, let pool = safeAdaptor.pixelBufferPool {
                            var compositeBuffer: CVPixelBuffer?
                            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &compositeBuffer)

                            if status == kCVReturnSuccess, let compositeBuffer {
                                let background = CIImage(cvPixelBuffer: sourcePixelBuffer)
                                let overlay = CIImage(cgImage: overlayImage)
                                ciContext.render(overlay.composited(over: background), to: compositeBuffer)
                                appended = safeAdaptor.append(compositeBuffer, withPresentationTime: presentationTime)
                            }
                        }
                    }

                    if !appended {
                        appended = safeVideoInput.append(sampleBuffer)
                    }

                    guard appended else {
                        errorBox.record(safeWriter.error ?? ExportStreamError.videoFrame(time: seconds))
                        if videoFinished.fire() {
                            safeVideoInput.markAsFinished()
                            dispatchGroup.leave()
                        }
                        stop = true
                        return
                    }

                    let percentage = Int((seconds / durationSeconds) * 100)
                    if percentage != lastLoggedPercentage, percentage % 10 == 0 {
                        lastLoggedPercentage = percentage
                        Log.debug("Export progress: \(percentage)%")
                    }

                    DispatchQueue.main.async {
                        self.exportProgress = min(1.0, max(0.0, seconds / durationSeconds))
                    }
                }

                if stop { break }
            }

            // If we stopped because of cancellation or a writer failure, make sure the
            // group is released — otherwise the export would wait forever.
            let terminal = cancelFlag.isSet || errorBox.error != nil || safeWriter.status == .failed
            if terminal, videoFinished.fire() {
                safeVideoInput.markAsFinished()
                dispatchGroup.leave()
            }
        }

        // MARK: Audio pump

        if let audioInput, let audioOutput {
            nonisolated(unsafe) let safeAudioInput = audioInput
            nonisolated(unsafe) let safeAudioOutput = audioOutput

            dispatchGroup.enter()
            safeAudioInput.requestMediaDataWhenReady(on: audioQueue) {
                while safeAudioInput.isReadyForMoreMediaData && !cancelFlag.isSet && errorBox.error == nil {
                    guard let sampleBuffer = safeAudioOutput.copyNextSampleBuffer() else {
                        if audioFinished.fire() {
                            safeAudioInput.markAsFinished()
                            dispatchGroup.leave()
                        }
                        return
                    }

                    guard safeAudioInput.append(sampleBuffer) else {
                        errorBox.record(safeWriter.error ?? ExportStreamError.audio)
                        if audioFinished.fire() {
                            safeAudioInput.markAsFinished()
                            dispatchGroup.leave()
                        }
                        return
                    }
                }

                let terminal = cancelFlag.isSet || errorBox.error != nil || safeWriter.status == .failed
                if terminal, audioFinished.fire() {
                    safeAudioInput.markAsFinished()
                    dispatchGroup.leave()
                }
            }
        }

        // MARK: Completion

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dispatchGroup.notify(queue: .main) {
                continuation.resume()
            }
        }

        if cancelFlag.isSet {
            writer.cancelWriting()
            reader.cancelReading()
            throw ExportStreamError.cancelled
        }

        if let error = errorBox.error {
            writer.cancelWriting()
            throw error
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? NSError(
                domain: "360VideoStitcher",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "The decoder failed while reading the source video."]
            )
        }

        if writer.status == .failed {
            throw writer.error ?? NSError(
                domain: "360VideoStitcher",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "The encoder failed while writing the output file."]
            )
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? NSError(
                domain: "360VideoStitcher",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "The output file could not be finalised."]
            )
        }

        exportProgress = 1.0
        Log.debug("Export finished: \(job.outputUrl.path)")
    }
}
