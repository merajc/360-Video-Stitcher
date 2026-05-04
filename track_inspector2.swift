import AVFoundation

let url = URL(fileURLWithPath: "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360")
let asset = AVURLAsset(url: url)

let group = DispatchGroup()
group.enter()

Task {
    do {
        let tracks = try await asset.loadTracks(withMediaType: .metadata)
        print("Found \(tracks.count) metadata tracks.")
        for track in tracks {
            let formatDescriptions = try await track.load(.formatDescriptions)
            for desc in formatDescriptions {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                let subTypeString = String(format: "%c%c%c%c",
                                           (mediaSubType >> 24) & 0xff,
                                           (mediaSubType >> 16) & 0xff,
                                           (mediaSubType >> 8) & 0xff,
                                           mediaSubType & 0xff)
                print("Track ID: \(track.trackID), Subtype: \(subTypeString)")
            }
        }
        
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
