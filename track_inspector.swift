import Foundation
import AVFoundation

func inspectTracks() async {
    let path = "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"
    let url = URL(fileURLWithPath: path)
    
    let tempDir = FileManager.default.temporaryDirectory
    let tempUrl = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    
    do {
        try FileManager.default.createSymbolicLink(at: tempUrl, withDestinationURL: url)
    } catch {
        print("Failed to create symlink: \(error)")
        return
    }
    
    let asset = AVURLAsset(url: tempUrl)
    
    do {
        let tracks = try await asset.load(.tracks)
        
        for (i, track) in tracks.enumerated() {
            let mediaType = track.mediaType.rawValue
            let formats = try await track.load(.formatDescriptions)
            var subtypes = [String]()
            for format in formats {
                let subtype = CMFormatDescriptionGetMediaSubType(format)
                
                let string = String(format: "%c%c%c%c",
                                    (subtype >> 24) & 0xff,
                                    (subtype >> 16) & 0xff,
                                    (subtype >> 8)  & 0xff,
                                    subtype         & 0xff)
                subtypes.append(string)
            }
            print("Track \(i): mediaType = \(mediaType), subtypes = \(subtypes)")
        }
    } catch {
        print("Error loading tracks: \(error)")
    }
    
    try? FileManager.default.removeItem(at: tempUrl)
}

Task {
    await inspectTracks()
    exit(0)
}

RunLoop.main.run()
