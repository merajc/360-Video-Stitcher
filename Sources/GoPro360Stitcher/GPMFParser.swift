import Foundation
import CoreMedia
import CoreLocation

struct GPSData {
    let timestamp: CMTime
    let coordinate: CLLocationCoordinate2D
    let altitude: Double
    let speed: Double
    let speed3D: Double
    // Raw accelerometer axes in m/s² (from ACCL stream)
    // GoPro MAX orientation: X=lateral, Y=vertical, Z=longitudinal
    var accelX: Double = 0.0
    var accelY: Double = 0.0
    var accelZ: Double = 0.0
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
        var allAccelData: [AccelSample] = []
        var currentTime = CMTime(value: 0, timescale: Int32(timescale))
        
        for sample in samples {
            if let data = parser.readSampleData(sample: sample) {
                let blockDuration = CMTime(value: Int64(sample.duration), timescale: Int32(timescale))
                let (blockGPS, blockAccel) = parseGPMF(data: data, pts: currentTime, blockDuration: blockDuration)
                allGPSData.append(contentsOf: blockGPS)
                allAccelData.append(contentsOf: blockAccel)
            }
            currentTime = CMTimeAdd(currentTime, CMTime(value: Int64(sample.duration), timescale: Int32(timescale)))
        }
        
        // Sort to ensure monotonic timestamps before merging
        allGPSData.sort { $0.timestamp.seconds < $1.timestamp.seconds }
        allAccelData.sort { $0.timestamp.seconds < $1.timestamp.seconds }
        
        // Merge accelerometer data onto GPS points by nearest timestamp
        // ACCL runs at ~200Hz, GPS5 at ~18Hz — downsample ACCL to GPS timestamps
        if !allAccelData.isEmpty {
            var accelIdx = 0
            for i in 0..<allGPSData.count {
                let gpsTime = allGPSData[i].timestamp.seconds
                // Advance accel index to nearest match
                while accelIdx + 1 < allAccelData.count &&
                      abs(allAccelData[accelIdx + 1].timestamp.seconds - gpsTime) <=
                      abs(allAccelData[accelIdx].timestamp.seconds - gpsTime) {
                    accelIdx += 1
                }
                if accelIdx < allAccelData.count {
                    let accel = allAccelData[accelIdx]
                    allGPSData[i].accelX = accel.x
                    allGPSData[i].accelY = accel.y
                    allGPSData[i].accelZ = accel.z
                }
            }
            print("📐 [GPMF] Merged \(allAccelData.count) ACCL → \(allGPSData.count) GPS. First ACCL raw: x=\(String(format: "%.2f", allAccelData[0].x)) y=\(String(format: "%.2f", allAccelData[0].y)) z=\(String(format: "%.2f", allAccelData[0].z)). First GPS.accel: x=\(String(format: "%.2f", allGPSData[0].accelX)) y=\(String(format: "%.2f", allGPSData[0].accelY)) z=\(String(format: "%.2f", allGPSData[0].accelZ))")
        }
        
        print("✅ [GPMF] Extraction finished. Found \(allGPSData.count) GPS points.")
        return allGPSData
    }
    
    private struct AccelSample {
        let timestamp: CMTime
        let x: Double
        let y: Double
        let z: Double
    }
    
    private func parseGPMF(data: Data, pts: CMTime, blockDuration: CMTime) -> ([GPSData], [AccelSample]) {
        var gpsResults: [GPSData] = []
        var accelResults: [AccelSample] = []
        
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
                    
                    if keyStr == "SCAL" {
                        currentScales = []
                        if (typeChar == "l" || typeChar == "L") && size == 4 {
                            // Int32 scales (used by GPS5)
                            for j in 0..<count {
                                let start = i + j * 4
                                let scale = data[start..<start+4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                currentScales.append(scale)
                            }
                        } else if (typeChar == "s" || typeChar == "S") && size == 2 {
                            // Int16 scales (used by ACCL, GYRO)
                            for j in 0..<count {
                                let start = i + j * 2
                                let scale = data[start..<start+2].withUnsafeBytes { $0.loadUnaligned(as: Int16.self).bigEndian }
                                currentScales.append(Int32(scale))
                            }
                        }
                    }
                    
                    // GPS5: lat, lon, alt, speed2d, speed3d (5 x Int32 = 20 bytes per sample)
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
                                
                                // Ignore points with no valid GPS lock (typically near 0.0, 0.0 or poles)
                                if (abs(flat) > 0.01 || abs(flon) > 0.01) && abs(flat) < 89.9 {
                                    let fraction = numSamples > 1 ? Double(j) / Double(numSamples - 1) : 0.0
                                    let sampleTime = CMTimeAdd(pts, CMTimeMultiplyByFloat64(blockDuration, multiplier: fraction))
                                    
                                    let gpsData = GPSData(
                                        timestamp: sampleTime,
                                        coordinate: CLLocationCoordinate2D(latitude: flat, longitude: flon),
                                        altitude: falt,
                                        speed: fspeed,
                                        speed3D: fspeed3d
                                    )
                                    gpsResults.append(gpsData)
                                }
                            }
                        }
                    }
                    
                    // ACCL: 3-axis accelerometer (3 x Int16 = 6 bytes per sample)
                    if keyStr == "ACCL" && typeChar == "s" && size == 6 {
                        let numSamples = count
                        // ACCL uses the most recent SCAL (typically a single value)
                        let accelScale = currentScales.first.map { Double($0) } ?? 1.0
                        if numSamples > 0 {
                            for j in 0..<numSamples {
                                let start = i + j * 6
                                guard start + 6 <= end else { break }
                                let ax = data[start..<start+2].withUnsafeBytes { $0.loadUnaligned(as: Int16.self).bigEndian }
                                let ay = data[start+2..<start+4].withUnsafeBytes { $0.loadUnaligned(as: Int16.self).bigEndian }
                                let az = data[start+4..<start+6].withUnsafeBytes { $0.loadUnaligned(as: Int16.self).bigEndian }
                                
                                let fraction = numSamples > 1 ? Double(j) / Double(numSamples - 1) : 0.0
                                let sampleTime = CMTimeAdd(pts, CMTimeMultiplyByFloat64(blockDuration, multiplier: fraction))
                                
                                accelResults.append(AccelSample(
                                    timestamp: sampleTime,
                                    x: Double(ax) / accelScale,
                                    y: Double(ay) / accelScale,
                                    z: Double(az) / accelScale
                                ))
                            }
                        }
                    }
                }
                
                i += paddedLen
            }
        }
        
        parseKLV(offset: 0, length: data.count)
        return (gpsResults, accelResults)
    }
}
