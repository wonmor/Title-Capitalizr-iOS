//
//  Zip.swift
//  Title Capitalizr
//
//  A minimal ZIP reader (stored and deflated entries) and writer (stored entries)
//  for .docx files. Inflate uses Apple's Compression framework, whose ZLIB codec is
//  raw DEFLATE, exactly what ZIP method 8 stores. No third-party code.
//

import Foundation
import Compression

enum ZipError: Error, Equatable {
    case notAZip
    case corrupt(String)
    case unsupportedMethod(UInt16)
    case missingEntry(String)
}

struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    let entries: [String: Entry]

    var entryNames: [String] { entries.keys.sorted() }

    init(data: Data) throws {
        let b = [UInt8](data)
        guard b.count >= 22, b[0] == 0x50, b[1] == 0x4B else { throw ZipError.notAZip }
        // End of central directory: scan backwards (the comment can be up to 64 KB).
        var eocd = -1
        var i = b.count - 22
        let floor = max(0, b.count - 22 - 65_535)
        while i >= floor {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.corrupt("no end of central directory") }
        let count = Int(Self.u16(b, eocd + 10))
        var p = Int(Self.u32(b, eocd + 16))
        var found: [String: Entry] = [:]
        for _ in 0..<count {
            guard p + 46 <= b.count, Self.u32(b, p) == 0x0201_4B50 else { throw ZipError.corrupt("bad central header") }
            let method = Self.u16(b, p + 10)
            let csize = Int(Self.u32(b, p + 20))
            let usize = Int(Self.u32(b, p + 24))
            let nameLen = Int(Self.u16(b, p + 28))
            let extraLen = Int(Self.u16(b, p + 30))
            let commentLen = Int(Self.u16(b, p + 32))
            let offset = Int(Self.u32(b, p + 42))
            guard p + 46 + nameLen <= b.count else { throw ZipError.corrupt("name out of range") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            found[name] = Entry(name: name, method: method, compressedSize: csize, uncompressedSize: usize, localHeaderOffset: offset)
            p += 46 + nameLen + extraLen + commentLen
        }
        self.bytes = b
        self.entries = found
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    func data(for name: String) throws -> Data {
        guard let e = entries[name] else { throw ZipError.missingEntry(name) }
        let h = e.localHeaderOffset
        guard h + 30 <= bytes.count, Self.u32(bytes, h) == 0x0403_4B50 else { throw ZipError.corrupt("bad local header for \(name)") }
        let start = h + 30 + Int(Self.u16(bytes, h + 26)) + Int(Self.u16(bytes, h + 28))
        guard start + e.compressedSize <= bytes.count else { throw ZipError.corrupt("entry \(name) out of range") }
        let slice = Array(bytes[start..<(start + e.compressedSize)])
        switch e.method {
        case 0:
            return Data(slice)
        case 8:
            return try Self.inflate(slice, expected: e.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod(e.method)
        }
    }

    func string(for name: String) throws -> String {
        String(decoding: try data(for: name), as: UTF8.self)
    }

    static func inflate(_ input: [UInt8], expected: Int) throws -> Data {
        if expected == 0 { return Data() }
        var out = [UInt8](repeating: 0, count: expected)
        let written = input.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, expected, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else { throw ZipError.corrupt("inflate produced \(written) of \(expected) bytes") }
        return Data(out)
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}

/// Writes a ZIP with stored (uncompressed) entries, which every Office reader accepts.
struct ZipWriter {
    private var files: [(name: String, data: Data)] = []

    mutating func add(_ name: String, _ data: Data) { files.append((name, data)) }
    mutating func add(_ name: String, _ text: String) { add(name, Data(text.utf8)) }

    func finalize(date: Date = Date()) -> Data {
        var out = [UInt8]()
        var central = [UInt8]()
        let (dosTime, dosDate) = Self.dosDateTime(date)
        for f in files {
            let name = [UInt8](f.name.utf8)
            let body = [UInt8](f.data)
            let crc = CRC32.checksum(body)
            let offset = UInt32(out.count)
            // Local file header
            out += le32(0x0403_4B50); out += le16(20); out += le16(0x0800); out += le16(0)
            out += le16(dosTime); out += le16(dosDate); out += le32(crc)
            out += le32(UInt32(body.count)); out += le32(UInt32(body.count))
            out += le16(UInt16(name.count)); out += le16(0)
            out += name; out += body
            // Central directory record
            central += le32(0x0201_4B50); central += le16(20); central += le16(20); central += le16(0x0800); central += le16(0)
            central += le16(dosTime); central += le16(dosDate); central += le32(crc)
            central += le32(UInt32(body.count)); central += le32(UInt32(body.count))
            central += le16(UInt16(name.count)); central += le16(0); central += le16(0)
            central += le16(0); central += le16(0); central += le32(0); central += le32(offset)
            central += name
        }
        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50); out += le16(0); out += le16(0)
        out += le16(UInt16(files.count)); out += le16(UInt16(files.count))
        out += le32(UInt32(central.count)); out += le32(cdOffset); out += le16(0)
        return Data(out)
    }

    private func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | ((c.second ?? 0) / 2))
        let year = max(1980, c.year ?? 1980)
        let day = UInt16((year - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
