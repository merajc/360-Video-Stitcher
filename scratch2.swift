import AVFoundation

let exporter = AVAssetExportSession(asset: AVMutableComposition(), presetName: AVAssetExportPresetHEVCHighestQuality)
if let e = exporter {
    print("HEVC Exporter created")
}
