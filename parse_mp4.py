import struct
import sys
import os

def parse_mp4(filepath):
    filesize = os.path.getsize(filepath)
    with open(filepath, 'rb') as f:
        read_boxes(f, filesize, "")

def read_boxes(f, end_offset, prefix):
    while f.tell() < end_offset:
        header = f.read(8)
        if len(header) < 8:
            break
        size, box_type = struct.unpack('>I4s', header)
        box_type = box_type.decode('ascii', errors='replace')
        
        if size == 1:
            size = struct.unpack('>Q', f.read(8))[0]
            header_size = 16
        elif size == 0:
            size = end_offset - f.tell() + 8
            header_size = 8
        else:
            header_size = 8
            
        print(f"{prefix}Box: {box_type}, size: {size}")
        
        if box_type in ['moov', 'trak', 'mdia', 'minf', 'stbl', 'mvex']:
            read_boxes(f, f.tell() + size - header_size, prefix + "  ")
        elif box_type == 'hdlr':
            f.read(4) # version and flags
            f.read(4) # pre_defined
            handler_type = f.read(4).decode('ascii', errors='replace')
            print(f"{prefix}  Handler type: {handler_type}")
            f.seek(size - header_size - 12, 1)
        elif box_type == 'stsd':
            f.read(4) # version and flags
            entry_count = struct.unpack('>I', f.read(4))[0]
            print(f"{prefix}  Sample Descriptions: {entry_count}")
            for _ in range(entry_count):
                desc_size, desc_format = struct.unpack('>I4s', f.read(8))
                desc_format = desc_format.decode('ascii', errors='replace')
                print(f"{prefix}    Format: {desc_format}")
                f.seek(desc_size - 8, 1)
        else:
            f.seek(size - header_size, 1)

if __name__ == '__main__':
    parse_mp4("/Users/merajchhaya/Pictures/Porsche track day April 2026/GS010014.360")
