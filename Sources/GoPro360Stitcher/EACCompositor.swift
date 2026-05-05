import AVFoundation
import CoreVideo
import Metal
import CoreImage

final class EACInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = false
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    var topPan: Float = 0
    var topTilt: Float = 0
    var topRoll: Float = 0
    var topFOV: Float = 90
    var topFlipH: Bool = false
    var topFlipV: Bool = false
    
    var bottomPan: Float = 0
    var bottomTilt: Float = 0
    var bottomRoll: Float = 0
    var bottomFOV: Float = 90
    var bottomFlipH: Bool = false
    var bottomFlipV: Bool = false
    
    init(timeRange: CMTimeRange, sourceTrackIDs: [NSValue]) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = sourceTrackIDs
    }
}

final class EACCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let renderQueue = DispatchQueue(label: "com.antigravity.EACCompositor.renderQueue")
    private var renderContext: AVVideoCompositionRenderContext?
    private let renderer = EACRenderer()
    
    var sourcePixelBufferAttributes: [String : any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    
    var requiredPixelBufferAttributesForRenderContext: [String : any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync {
            self.renderContext = newRenderContext
        }
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            autoreleasepool {
                self.processRequest(request)
            }
        }
    }
    
    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "EACCompositor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"]))
            return
        }
        
        let sourceTrackIDs = request.sourceTrackIDs
        
        // We expect Track 0 (Front) and Track 1 (Rear)
        var frontBuffer: CVPixelBuffer?
        var rearBuffer: CVPixelBuffer?
        
        if sourceTrackIDs.count >= 2 {
            frontBuffer = request.sourceFrame(byTrackID: sourceTrackIDs[0].int32Value)
            rearBuffer = request.sourceFrame(byTrackID: sourceTrackIDs[1].int32Value)
        }
        
        var topParams = SIMD4<Float>(0, 0, 0, 90)
        var bottomParams = SIMD4<Float>(0, 0, 0, 90)
        // flipFlags: x=topFlipH, y=topFlipV, z=bottomFlipH, w=bottomFlipV
        var flipFlags = SIMD4<Float>(0, 0, 0, 0)
        
        if let instr = request.videoCompositionInstruction as? EACInstruction {
            topParams = SIMD4<Float>(instr.topTilt, instr.topPan, instr.topRoll, instr.topFOV)
            bottomParams = SIMD4<Float>(instr.bottomTilt, instr.bottomPan, instr.bottomRoll, instr.bottomFOV)
            flipFlags = SIMD4<Float>(
                instr.topFlipH ? 1.0 : 0.0,
                instr.topFlipV ? 1.0 : 0.0,
                instr.bottomFlipH ? 1.0 : 0.0,
                instr.bottomFlipV ? 1.0 : 0.0
            )
        }
        
        if let front = frontBuffer, let rear = rearBuffer {
            renderer?.renderStacked(front: front, rear: rear, to: outputBuffer, topParams: topParams, bottomParams: bottomParams, flipFlags: flipFlags)
            request.finish(withComposedVideoFrame: outputBuffer)
        } else {
            // Fallback: use whatever we have
            if let firstID = sourceTrackIDs.first?.int32Value,
               let buffer = request.sourceFrame(byTrackID: firstID) {
                renderer?.renderStacked(front: buffer, rear: buffer, to: outputBuffer, topParams: topParams, bottomParams: bottomParams, flipFlags: flipFlags)
                request.finish(withComposedVideoFrame: outputBuffer)
            } else {
                request.finish(with: NSError(domain: "EACCompositor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing source frames"]))
            }
        }
    }
}
