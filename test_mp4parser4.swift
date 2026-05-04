import Foundation

class MP4BoxParser {
    let url: URL
    private var fileHandle: FileHandle?
    
    init(url: URL) {
        self.url = url
    }
    
    func extractGPMFSamples() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        self.fileHandle = handle
        
        do {
            let fileSize = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
            
            try parseBoxes(endOffset: fileSize, targetFormat: "gpmd", depth: 0)
        } catch {
            print("⚠️ [MP4BoxParser] Error: \(error)")
        }
    }
    
    var trakStart: UInt64 = 0
    var trakSize: UInt64 = 0
    
    private func parseBoxes(endOffset: UInt64, targetFormat: String, depth: Int) throws {
        guard let handle = fileHandle else { return }
        
        while try handle.offset() < endOffset {
            let offset = try handle.offset()
            guard let header = try handle.read(upToCount: 8), header.count == 8 else { break }
            
            var size = UInt64(header[0...3].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
            let type = String(data: header[4...7], encoding: .ascii) ?? ""
            
            var headerSize: UInt64 = 8
            if size == 1 {
                guard let extSizeData = try handle.read(upToCount: 8) else { break }
                size = extSizeData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                headerSize = 16
            } else if size == 0 {
                size = endOffset - offset
            }
            
            let nextOffset = offset + size
            let prefix = String(repeating: "  ", count: depth)
            
            if type == "trak" {
                trakStart = offset
                trakSize = size
            }
            
            if type == "moov" || type == "trak" || type == "mdia" || type == "minf" || type == "stbl" {
                try handle.seek(toOffset: offset + headerSize)
                try parseBoxes(endOffset: nextOffset, targetFormat: targetFormat, depth: depth + 1)
            } else if type == "stsd" {
                try handle.seek(toOffset: offset + headerSize + 4)
                if let countData = try handle.read(upToCount: 4) {
                    let entryCount = countData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                    var found = false
                    for _ in 0..<entryCount {
                        if let entryHeader = try handle.read(upToCount: 8) {
                            let entrySize = entryHeader[0...3].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                            let format = String(data: entryHeader[4...7], encoding: .ascii) ?? ""
                            if format == targetFormat {
                                found = true
                            }
                            try handle.seek(toOffset: try handle.offset() + UInt64(entrySize) - 8)
                        }
                    }
                    if found {
                        print("Found \(targetFormat) at trakStart: \(trakStart), size: \(trakSize)")
                        try extractSamplesFromTrak(trakStart: trakStart, trakEnd: trakStart + trakSize)
                    }
                }
            }
            
            try handle.seek(toOffset: nextOffset)
        }
    }
    
    private func extractSamplesFromTrak(trakStart: UInt64, trakEnd: UInt64) throws {
        guard let handle = fileHandle else { return }
        
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
                var size = UInt64(header[0...3].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                let type = String(data: header[4...7], encoding: .ascii) ?? ""
                var headerSize: UInt64 = 8
                if size == 1 {
                    guard let extSize = try handle.read(upToCount: 8) else { break }
                    size = extSize.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                    headerSize = 16
                }
                let nextOffset = offset + size
                
                if type == "mdia" || type == "minf" || type == "stbl" {
                    try handle.seek(toOffset: offset + headerSize)
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
        print("Tables parsed:")
        print("mdhd: \(mdhd != nil), stts: \(stts != nil), stsc: \(stsc != nil), stsz: \(stsz != nil), stco: \(stco != nil), co64: \(co64 != nil)")
    }
}

let parser = MP4BoxParser(url: URL(fileURLWithPath: "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"))
parser.extractGPMFSamples()
