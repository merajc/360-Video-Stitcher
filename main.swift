import Foundation

func parseKLV(data: Data, offset: Int, length: Int, indent: String = "") {
    var i = offset
    let end = offset + length
    
    var currentScales: [Int32] = []
    
    while i + 8 <= end {
        let keyStr = String(data: data[i..<i+4], encoding: .ascii) ?? "????"
        let type = data[i+4]
        let size = Int(data[i+5])
        let count = Int(data[i+6...i+7].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian })
        let payloadLen = size * count
        let paddedLen = (payloadLen + 3) & ~3
        
        i += 8
        if i + payloadLen > end {
            break
        }
        
        if type == 0 {
            print("\(indent)\(keyStr) (Nested)")
            parseKLV(data: data, offset: i, length: payloadLen, indent: indent + "  ")
        } else {
            let typeChar = String(bytes: [type], encoding: .ascii) ?? "?"
            print("\(indent)\(keyStr) type: '\(typeChar)', size: \(size), count: \(count)")
            
            if keyStr == "SCAL" && (typeChar == "l" || typeChar == "L") && size == 4 {
                currentScales = []
                for j in 0..<count {
                    let start = i + j*4
                    let scale = data[start..<start+4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                    currentScales.append(scale)
                }
                print("\(indent)  Scales: \(currentScales)")
            }
            if keyStr == "GPS5" && typeChar == "l" && size == 4 {
                let numSamples = count / 5
                print("\(indent)  \(numSamples) GPS samples")
                if numSamples > 0 && currentScales.count >= 5 {
                    for j in 0..<min(2, numSamples) {
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
                        print("\(indent)    Lat: \(flat), Lon: \(flon), Alt: \(falt), Speed: \(fspeed)")
                    }
                }
            }
        }
        
        i += paddedLen
    }
}

let parser = MP4BoxParser(url: URL(fileURLWithPath: "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"))
if let (samples, timescale) = parser.extractGPMFSamples() {
    if let firstSample = samples.first, let data = parser.readSampleData(sample: firstSample) {
        parseKLV(data: data, offset: 0, length: data.count)
    }
}
