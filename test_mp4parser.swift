import Foundation

struct MP4Sample {
    let offset: UInt64
    let size: UInt32
    let duration: UInt32 // in timescale units
    let decodingTime: UInt64 // in timescale units
}

class MP4BoxParser {
    let url: URL
    private var fileHandle: FileHandle?
    
    init(url: URL) {
        self.url = url
    }
    
    func extractGPMFSamples() -> ([MP4Sample], UInt32)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.fileHandle = handle
        defer {
            try? handle.close()
        }
        
        do {
            let fileSize = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
            
            return try parseBoxes(endOffset: fileSize, targetFormat: "gpmd")
        } catch {
            print("⚠️ [MP4BoxParser] Error: \(error)")
            return nil
        }
    }
    
    func readSampleData(sample: MP4Sample) -> Data? {
        guard let handle = fileHandle else { return nil }
        do {
            try handle.seek(toOffset: sample.offset)
            return try handle.read(upToCount: Int(sample.size))
        } catch {
            return nil
        }
    }
    
    private func parseBoxes(endOffset: UInt64, targetFormat: String) throws -> ([MP4Sample], UInt32)? {
        guard let handle = fileHandle else { return nil }
        
        var trakStart: UInt64 = 0
        var trakSize: UInt64 = 0
        
        while try handle.offset() < endOffset {
            let offset = try handle.offset()
            guard let header = try handle.read(upToCount: 8), header.count == 8 else { break }
            
            var size = UInt64(header[0...3].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            let type = String(data: header[4...7], encoding: .ascii) ?? ""
            
            var headerSize: UInt64 = 8
            if size == 1 {
                guard let extSizeData = try handle.read(upToCount: 8) else { break }
                size = extSizeData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                headerSize = 16
            } else if size == 0 {
                size = endOffset - offset
            }
            
            let nextOffset = offset + size
            
            if type == "moov" || type == "trak" || type == "mdia" || type == "minf" || type == "stbl" {
                if type == "trak" {
                    trakStart = offset
                    trakSize = size
                }
                
                if let result = try parseBoxes(endOffset: nextOffset, targetFormat: targetFormat) {
                    return result
                }
            } else if type == "stsd" {
                // Check if format matches targetFormat
                try handle.seek(toOffset: offset + headerSize + 4) // skip version/flags
                guard let countData = try handle.read(upToCount: 4) else { continue }
                let entryCount = countData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                
                var found = false
                for _ in 0..<entryCount {
                    guard let entryHeader = try handle.read(upToCount: 8) else { break }
                    let entrySize = entryHeader[0...3].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    let format = String(data: entryHeader[4...7], encoding: .ascii) ?? ""
                    if format == targetFormat {
                        found = true
                        break
                    }
                    try handle.seek(toOffset: try handle.offset() + UInt64(entrySize) - 8)
                }
                
                if found {
                    // This trak has the target format! We need to parse stts, stsc, stsz, stco
                    return try extractSamplesFromTrak(trakStart: trakStart, trakEnd: trakStart + trakSize)
                }
            }
            
            try handle.seek(toOffset: nextOffset)
        }
        return nil
    }
    
    private func extractSamplesFromTrak(trakStart: UInt64, trakEnd: UInt64) throws -> ([MP4Sample], UInt32)? {
        guard let handle = fileHandle else { return nil }
        
        var stts: Data?
        var stsc: Data?
        var stsz: Data?
        var stco: Data?
        var co64: Data?
        var mdhd: Data?
        
        try handle.seek(toOffset: trakStart)
        
        func findTables(endOffset: UInt64) throws {
            while try handle.offset() < endOffset {
                let offset = try handle.offset()
                guard let header = try handle.read(upToCount: 8), header.count == 8 else { break }
                var size = UInt64(header[0...3].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                let type = String(data: header[4...7], encoding: .ascii) ?? ""
                var headerSize: UInt64 = 8
                if size == 1 {
                    guard let extSize = try handle.read(upToCount: 8) else { break }
                    size = extSize.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                    headerSize = 16
                }
                let nextOffset = offset + size
                
                if type == "mdia" || type == "minf" || type == "stbl" {
                    try findTables(endOffset: nextOffset)
                } else if type == "mdhd" {
                    try handle.seek(toOffset: offset + headerSize)
                    mdhd = try handle.read(upToCount: Int(size - headerSize))
                } else if type == "stts" {
                    try handle.seek(toOffset: offset + headerSize)
                    stts = try handle.read(upToCount: Int(size - headerSize))
                } else if type == "stsc" {
                    try handle.seek(toOffset: offset + headerSize)
                    stsc = try handle.read(upToCount: Int(size - headerSize))
                } else if type == "stsz" {
                    try handle.seek(toOffset: offset + headerSize)
                    stsz = try handle.read(upToCount: Int(size - headerSize))
                } else if type == "stco" {
                    try handle.seek(toOffset: offset + headerSize)
                    stco = try handle.read(upToCount: Int(size - headerSize))
                } else if type == "co64" {
                    try handle.seek(toOffset: offset + headerSize)
                    co64 = try handle.read(upToCount: Int(size - headerSize))
                }
                
                try handle.seek(toOffset: nextOffset)
            }
        }
        
        try findTables(endOffset: trakEnd)
        
        guard let mdhdData = mdhd, let sttsData = stts, let stscData = stsc, let stszData = stsz else { return nil }
        let hasOffsets = stco != nil || co64 != nil
        guard hasOffsets else { return nil }
        
        let version = mdhdData[0]
        var timescale: UInt32 = 0
        if version == 1 {
            timescale = mdhdData[20...23].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        } else {
            timescale = mdhdData[12...15].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }
        
        let sampleSize = stszData[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let sampleCount = stszData[8...11].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        var sizes: [UInt32] = []
        if sampleSize == 0 {
            for i in 0..<Int(sampleCount) {
                let start = 12 + i * 4
                sizes.append(stszData[start..<start+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            }
        } else {
            sizes = Array(repeating: sampleSize, count: Int(sampleCount))
        }
        
        var chunkOffsets: [UInt64] = []
        if let co64Data = co64 {
            let count = co64Data[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            for i in 0..<Int(count) {
                let start = 8 + i * 8
                chunkOffsets.append(co64Data[start..<start+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            }
        } else if let stcoData = stco {
            let count = stcoData[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            for i in 0..<Int(count) {
                let start = 8 + i * 4
                chunkOffsets.append(UInt64(stcoData[start..<start+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }))
            }
        }
        
        let stscCount = stscData[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        struct STSCEntry {
            let firstChunk: UInt32
            let samplesPerChunk: UInt32
        }
        var stscEntries: [STSCEntry] = []
        for i in 0..<Int(stscCount) {
            let start = 8 + i * 12
            let firstChunk = stscData[start..<start+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let samplesPerChunk = stscData[start+4..<start+8].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            stscEntries.append(STSCEntry(firstChunk: firstChunk, samplesPerChunk: samplesPerChunk))
        }
        
        let sttsCount = sttsData[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        var sampleDurations: [(count: UInt32, delta: UInt32)] = []
        for i in 0..<Int(sttsCount) {
            let start = 8 + i * 8
            let count = sttsData[start..<start+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let delta = sttsData[start+4..<start+8].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            sampleDurations.append((count, delta))
        }
        
        var samples: [MP4Sample] = []
        var sampleIndex = 0
        var currentStscIndex = 0
        var currentTime: UInt64 = 0
        
        var durationIndex = 0
        var durationSamplesLeft = sampleDurations.isEmpty ? 0 : sampleDurations[0].count
        
        for chunkIndex in 0..<chunkOffsets.count {
            let currentChunk = UInt32(chunkIndex + 1)
            
            if currentStscIndex + 1 < stscEntries.count && currentChunk == stscEntries[currentStscIndex + 1].firstChunk {
                currentStscIndex += 1
            }
            
            let samplesInThisChunk = stscEntries[currentStscIndex].samplesPerChunk
            var currentOffset = chunkOffsets[chunkIndex]
            
            for _ in 0..<samplesInThisChunk {
                guard sampleIndex < sizes.count else { break }
                let size = sizes[sampleIndex]
                
                var duration: UInt32 = 0
                if durationSamplesLeft > 0 {
                    duration = sampleDurations[durationIndex].delta
                    durationSamplesLeft -= 1
                    if durationSamplesLeft == 0 && durationIndex + 1 < sampleDurations.count {
                        durationIndex += 1
                        durationSamplesLeft = sampleDurations[durationIndex].count
                    }
                }
                
                samples.append(MP4Sample(offset: currentOffset, size: size, duration: duration, decodingTime: currentTime))
                
                currentTime += UInt64(duration)
                currentOffset += UInt64(size)
                sampleIndex += 1
            }
        }
        
        return (samples, timescale)
    }
}

let parser = MP4BoxParser(url: URL(fileURLWithPath: "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"))
if let (samples, timescale) = parser.extractGPMFSamples() {
    print("Found \(samples.count) samples. Timescale: \(timescale)")
    if let first = samples.first {
        print("First sample offset: \(first.offset), size: \(first.size)")
        if let data = parser.readSampleData(sample: first) {
            print("First 16 bytes: \(Array(data.prefix(16)).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }
} else {
    print("No GPMF samples found.")
}
