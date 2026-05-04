import Foundation

let parser = MP4BoxParser(url: URL(fileURLWithPath: "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"))
if let (samples, timescale) = parser.extractGPMFSamples() {
    print("Found \(samples.count) samples. Timescale: \(timescale)")
    if let first = samples.first {
        print("First sample offset: \(first.offset), size: \(first.size)")
        if let data = parser.readSampleData(sample: first) {
            print("First 16 bytes: \(Array(data.prefix(16)).map { String(format: "%02x", $0) }.joined(separator: " "))")
            let str = String(data: data.prefix(16), encoding: .ascii) ?? ""
            print("String representation: \(str)")
        }
    }
} else {
    print("No GPMF samples found.")
}
