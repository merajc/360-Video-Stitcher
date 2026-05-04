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
            // print("\(prefix)\(type) (size: \(size))")
            
            if type == "moov" || type == "trak" || type == "mdia" || type == "minf" || type == "stbl" {
                try handle.seek(toOffset: offset + headerSize)
                try parseBoxes(endOffset: nextOffset, targetFormat: targetFormat, depth: depth + 1)
            } else if type == "stsd" {
                // Check if format matches targetFormat
                try handle.seek(toOffset: offset + headerSize + 4) // skip version/flags
                if let countData = try handle.read(upToCount: 4) {
                    let entryCount = countData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                    
                    for _ in 0..<entryCount {
                        if let entryHeader = try handle.read(upToCount: 8) {
                            let entrySize = entryHeader[0...3].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                            let format = String(data: entryHeader[4...7], encoding: .ascii) ?? ""
                            print("\(prefix)  -> stsd format: \(format)")
                            try handle.seek(toOffset: try handle.offset() + UInt64(entrySize) - 8)
                        }
                    }
                }
            }
            
            try handle.seek(toOffset: nextOffset)
        }
    }
}

let parser = MP4BoxParser(url: URL(fileURLWithPath: "/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360"))
parser.extractGPMFSamples()
