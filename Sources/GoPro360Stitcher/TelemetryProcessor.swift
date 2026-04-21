import Foundation
import AVFoundation
import CoreLocation

struct GPSPoint: Identifiable, Codable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let timestamp: Double // Elapsed time in seconds
}

class TelemetryProcessor: ObservableObject {
    @Published var trackPoints: [GPSPoint] = []
    
    // Normalized track bounds for drawing
    private(set) var minLat: Double = 0
    private(set) var maxLat: Double = 0
    private(set) var minLon: Double = 0
    private(set) var maxLon: Double = 0
    
    @MainActor
    func extractTelemetry(from asset: AVAsset) async {
        print("🛰 [Telemetry] Searching for GPMF track...")
        
        do {
            let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
            var gpsPoints: [GPSPoint] = []
            
            for track in metadataTracks {
                let formatDescs = try await track.load(.formatDescriptions)
                let isGPMF = formatDescs.contains { (desc: CMFormatDescription) in
                    desc.mediaSubType.rawValue == 0x67706d64 // 'gpmd'
                }
                
                if isGPMF {
                    print("🛰 [Telemetry] Found GPMF track. Reading samples...")
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                    reader.add(output)
                    reader.startReading()
                    
                    while let sampleBuffer = output.copyNextSampleBuffer() {
                        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                            let length = CMBlockBufferGetDataLength(blockBuffer)
                            var data = Data(count: length)
                            data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
                                _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
                            }
                            
                            // Basic GPMF GPS5 Parser
                            let points = parseGPMF(data, currentTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
                            gpsPoints.append(contentsOf: points)
                        }
                    }
                }
            }
            
            if !gpsPoints.isEmpty {
                await MainActor.run {
                    self.trackPoints = gpsPoints
                    self.calculateBounds()
                    print("🛰 [Telemetry] Extracted \(gpsPoints.count) GPS points.")
                }
            } else {
                print("⚠️ [Telemetry] No GPS points found.")
            }
            
        } catch {
            print("❌ [Telemetry] Extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func parseGPMF(_ data: Data, currentTime: Double) -> [GPSPoint] {
        var points: [GPSPoint] = []
        
        // GPMF is a recursive structure of Key-Type-Size-Count blocks
        // We look for 'GPS5' which contains [Lat, Lon, Alt, Spd, 3D_Spd]
        
        var offset = 0
        while offset + 8 <= data.count {
            let keyData = data.subdata(in: offset..<offset+4)
            let key = String(data: keyData, encoding: .ascii) ?? "????"
            let type = data[offset+4]
            let size = Int(data[offset+5])
            let count = Int(UInt16(bigEndian: data.subdata(in: offset+6..<offset+8).withUnsafeBytes { $0.load(as: UInt16.self) }))
            let blockSize = Int(size) * Int(count)
            
            if key == "STRM" {
                // Nested stream, parse contents
                let nestedData = data.subdata(in: offset+8..<offset+8+blockSize)
                points.append(contentsOf: parseGPMF(nestedData, currentTime: currentTime))
            } else if key == "GPS5" && type == 76 { // 'L' is signed long 32-bit
                // GPS5 usually follows a scaling factor (SCAL). 
                // For simplicity, we assume standard GoPro scaling (1.0e7 for deg)
                let sampleSize = 5 * 4 // 5 fields * 4 bytes
                for i in 0..<count {
                    let start = offset + 8 + (i * sampleSize)
                    if start + 20 <= data.count {
                        let latIdx = data.subdata(in: start..<start+4).withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) }
                        let lonIdx = data.subdata(in: start+4..<start+8).withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) }
                        let altIdx = data.subdata(in: start+8..<start+12).withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) }
                        let spdIdx = data.subdata(in: start+12..<start+16).withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) }
                        
                        points.append(GPSPoint(
                            latitude: Double(latIdx) / 10000000.0,
                            longitude: Double(lonIdx) / 10000000.0,
                            altitude: Double(altIdx) / 1000.0,
                            speed: Double(spdIdx) / 1000.0,
                            timestamp: currentTime
                        ))
                    }
                }
            }
            
            // Advance offset (GPMF blocks are 4-byte aligned)
            offset += 8 + ((blockSize + 3) & ~3)
        }
        
        return points
    }
    
    private func calculateBounds() {
        guard !trackPoints.isEmpty else { return }
        minLat = trackPoints.map { $0.latitude }.min() ?? 0
        maxLat = trackPoints.map { $0.latitude }.max() ?? 0
        minLon = trackPoints.map { $0.longitude }.min() ?? 0
        maxLon = trackPoints.map { $0.longitude }.max() ?? 0
    }
}
