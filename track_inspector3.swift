import AVFoundation
import Foundation

let originalPath = "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"
let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
try? FileManager.default.createSymbolicLink(at: tempURL, withDestinationURL: URL(fileURLWithPath: originalPath))

let asset = AVURLAsset(url: tempURL)

let group = DispatchGroup()
group.enter()

Task {
    do {
        let allTracks = try await asset.load(.tracks)
        print("Total tracks: \(allTracks.count)")
        for track in allTracks {
            let mediaType = track.mediaType
            let formatDescriptions = try await track.load(.formatDescriptions)
            var subTypeString = "Unknown"
            if let desc = formatDescriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                subTypeString = String(format: "%c%c%c%c",
                                       (mediaSubType >> 24) & 0xff,
                                       (mediaSubType >> 16) & 0xff,
                                       (mediaSubType >> 8) & 0xff,
                                       mediaSubType & 0xff)
            }
            print("Track ID: \(track.trackID), MediaType: \(mediaType.rawValue), Subtype: \(subTypeString)")
        }
    } catch {
        print("Error: \(error)")
    }
    group.leave()
}

group.wait()
