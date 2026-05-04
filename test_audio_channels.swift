import Foundation
import AVFoundation

func testAudio() async {
    let sourceFile = "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"
    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mp4")
    try? FileManager.default.createSymbolicLink(at: tempUrl, withDestinationURL: URL(fileURLWithPath: sourceFile))
    let asset = AVURLAsset(url: tempUrl)
    
    do {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        print("Found \(audioTracks.count) audio tracks")
        for (i, track) in audioTracks.enumerated() {
            let formatDescriptions = try await track.load(.formatDescriptions)
            for desc in formatDescriptions {
                if let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    print("Track \(i): \(streamDesc.pointee.mChannelsPerFrame) channels, \(streamDesc.pointee.mSampleRate) Hz")
                }
            }
        }
    } catch {
        print("Error: \(error)")
    }
}

let sema = DispatchSemaphore(value: 0)
Task {
    await testAudio()
    sema.signal()
}
sema.wait()
