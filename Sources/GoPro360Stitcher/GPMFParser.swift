import Foundation
import AVFoundation
import CoreLocation

struct GPSData {
    let timestamp: CMTime
    let coordinate: CLLocationCoordinate2D
    let altitude: Double
    let speed: Double
}

class GPMFParser {
    /// Extracts GPS5 data from a GoPro metadata track
    func extractGPSData(from asset: AVAsset) async throws -> [GPSData] {
        print("🗺 [GPMF] Scanning asset for telemetry tracks...")
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        
        var gpmdTrack: AVAssetTrack?
        for track in metadataTracks {
            let formats = try await track.load(.formatDescriptions)
            if formats.contains(where: { CMFormatDescriptionGetMediaSubType($0) == 0x67706d64 }) {
                gpmdTrack = track
                break
            }
        }
        
        guard let finalTrack = gpmdTrack else {
            print("⚠️ [GPMF] No 'gpmd' track found.")
            return []
        }
        
        print("🗺 [GPMF] Found GoPro Metadata track. Starting reader...")
        
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: finalTrack, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        
        print("🗺 [GPMF] Processing sample buffers...")
        var allGPSData: [GPSData] = []
        var sampleCount = 0
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            sampleCount += 1
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            var length = 0
            var totalLength = 0
            var dataPtr: UnsafeMutablePointer<Int8>?
            
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &dataPtr)
            
            if let ptr = dataPtr {
                let data = Data(bytes: ptr, count: totalLength)
                let samples = parseGPMF(data: data, pts: pts)
                allGPSData.append(contentsOf: samples)
            }
        }
        
        print("✅ [GPMF] Extraction finished. Processed \(sampleCount) blocks, found \(allGPSData.count) GPS points.")
        return allGPSData
    }
    
    // Simple KLV parser looking for 'GPS5'
    private func parseGPMF(data: Data, pts: CMTime) -> [GPSData] {
        var results: [GPSData] = []
        let gps5Key: [UInt8] = [0x47, 0x50, 0x53, 0x35] // "GPS5"
        
        var i = 0
        while i < data.count - 8 {
            let key = Array(data[i..<i+4])
            let type = data[i+4]
            let size = Int(data[i+5])
            let count = Int(UInt16(data[i+6]) << 8 | UInt16(data[i+7]))
            let totalPayloadSize = size * count
            
            i += 8
            if key == gps5Key {
                // GPS5 usually contains Latitude, Longitude, Altitude, Speed, 3D Speed
                // We expect floating point values (type 'f' = 0x66 or 'd' = 0x64 etc, but GoPro often uses scaled ints)
                // For this lightweight version, we'll assume standard GoPro GPS5 layout if found
                // Note: GoPro metadata is big-endian
                
                // This is a simplified extraction. Real GoPro GPS5 often needs scaling factors (SCAL key).
                // For brevity, we'll assume a fixed format or wait for user to provide sample files for better calibration.
                // Normally we'd look for the 'SCAL' sibling to get the divisors.
                
                // Placeholder: extract one coordinate per block at least for the track outline
                if totalPayloadSize >= 16 {
                    // Just a mock extraction logic for illustration
                    // In a production app, we would use the SCAL factors found earlier in the stream.
                }
            }
            
            // Advance to next KLV (padded to 4 bytes)
            i += (totalPayloadSize + 3) & ~3
        }
        
        return results
    }
}
