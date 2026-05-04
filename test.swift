import AVFoundation

func test() {
    nonisolated(unsafe) let x = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    x.requestMediaDataWhenReady(on: DispatchQueue.global()) {
        print(x.isReadyForMoreMediaData)
    }
}
