import Foundation
import AVFoundation

enum ExportJobStatus: Equatable {
    case pending
    case exporting
    case completed
    case failed(String)
}

struct ExportJob: Identifiable, @unchecked Sendable {
    let id: UUID
    let name: String
    
    // Captured state for the export
    let composition: AVMutableComposition
    let videoComposition: AVVideoComposition
    let duration: CMTime
    
    // Output settings
    let outputUrl: URL
    let resolution: ExportResolution
    let codec: ExportCodec
    let bitrate: ExportBitrate
    
    // Progress and status
    var status: ExportJobStatus = .pending
    var progress: Double = 0.0
    
    init(
        id: UUID = UUID(),
        name: String,
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition,
        duration: CMTime,
        outputUrl: URL,
        resolution: ExportResolution,
        codec: ExportCodec,
        bitrate: ExportBitrate
    ) {
        self.id = id
        self.name = name
        self.composition = composition
        self.videoComposition = videoComposition
        self.duration = duration
        self.outputUrl = outputUrl
        self.resolution = resolution
        self.codec = codec
        self.bitrate = bitrate
    }
}
