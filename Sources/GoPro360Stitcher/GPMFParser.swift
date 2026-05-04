import Foundation
import CoreMedia
import CoreLocation

struct GPSData {
    let timestamp: CMTime
    let coordinate: CLLocationCoordinate2D
    let altitude: Double
    let speed: Double
    let speed3D: Double
}

class GPMFParser {
    func extractGPSData(from url: URL) async -> [GPSData] {
        print("🗺 [GPMF] Scanning asset for telemetry tracks via native parser...")
        let parser = MP4BoxParser(url: url)
        
        guard let (samples, timescale) = parser.extractGPMFSamples() else {
            print("⚠️ [GPMF] No 'gpmd' track found.")
            return []
        }
        
        print("🗺 [GPMF] Found GoPro Metadata track. Processing \(samples.count) blocks...")
        
        var allGPSData: [GPSData] = []
        var currentTime = CMTime(value: 0, timescale: Int32(timescale))
        
        for sample in samples {
            if let data = parser.readSampleData(sample: sample) {
                // Parse the payload block, passing block duration for timestamp interpolation
                let blockDuration = CMTime(value: Int64(sample.duration), timescale: Int32(timescale))
                let blockGPS = parseGPMF(data: data, pts: currentTime, blockDuration: blockDuration)
                allGPSData.append(contentsOf: blockGPS)
            }
            currentTime = CMTimeAdd(currentTime, CMTime(value: Int64(sample.duration), timescale: Int32(timescale)))
        }
        
        print("✅ [GPMF] Extraction finished. Found \(allGPSData.count) GPS points.")
        return allGPSData
    }
    
    private func parseGPMF(data: Data, pts: CMTime, blockDuration: CMTime) -> [GPSData] {
        var results: [GPSData] = []
        
        // GPMF is KLV: Key(4), Type(1), Size(1), Count(2) -> 8 bytes
        var currentScales: [Int32] = []
        
        func parseKLV(offset: Int, length: Int) {
            var i = offset
            let end = offset + length
            
            while i + 8 <= end {
                let keyStr = String(data: data[i..<i+4], encoding: .ascii) ?? ""
                let type = data[i+4]
                let size = Int(data[i+5])
                let count = Int(data[i+6...i+7].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian })
                let payloadLen = size * count
                let paddedLen = (payloadLen + 3) & ~3
                
                i += 8
                if i + payloadLen > end { break }
                
                if type == 0 { // Nested structure
                    parseKLV(offset: i, length: payloadLen)
                } else {
                    let typeChar = String(bytes: [type], encoding: .ascii) ?? "?"
                    
                    if keyStr == "SCAL" && (typeChar == "l" || typeChar == "L") && size == 4 {
                        currentScales = []
                        for j in 0..<count {
                            let start = i + j * 4
                            let scale = data[start..<start+4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                            currentScales.append(scale)
                        }
                    }
                    
                    if keyStr == "GPS5" && typeChar == "l" && size == 20 {
                        let numSamples = count
                        if numSamples > 0 && currentScales.count >= 5 {
                            for j in 0..<numSamples {
                                let start = i + j * 20
                                let lat = data[start..<start+4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                let lon = data[start+4..<start+8].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                let alt = data[start+8..<start+12].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                let speed2d = data[start+12..<start+16].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                let speed3d = data[start+16..<start+20].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                
                                let flat = Double(lat) / Double(currentScales[0])
                                let flon = Double(lon) / Double(currentScales[1])
                                let falt = Double(alt) / Double(currentScales[2])
                                let fspeed = Double(speed2d) / Double(currentScales[3])
                                let fspeed3d = Double(speed3d) / Double(currentScales[4])
                                
                                // Interpolate timestamp within the block so each sample gets a distinct time
                                let fraction = numSamples > 1 ? Double(j) / Double(numSamples - 1) : 0.0
                                let sampleTime = CMTimeAdd(pts, CMTimeMultiplyByFloat64(blockDuration, multiplier: fraction))
                                
                                let gpsData = GPSData(
                                    timestamp: sampleTime,
                                    coordinate: CLLocationCoordinate2D(latitude: flat, longitude: flon),
                                    altitude: falt,
                                    speed: fspeed,
                                    speed3D: fspeed3d
                                )
                                results.append(gpsData)
                            }
                        }
                    }
                }
                
                i += paddedLen
            }
        }
        
        parseKLV(offset: 0, length: data.count)
        return results
    }
}
