import Foundation

public enum BatchMode: String, CaseIterable, Codable, Sendable { case lines, fileNames, csvColumn }

public struct BatchOptions: Equatable, Sendable {
    public var mode: BatchMode
    public var csvColumn: Int
    public var csvHasHeader: Bool
    public var skipEmpty: Bool

    public init(mode: BatchMode = .lines, csvColumn: Int = 0, csvHasHeader: Bool = true, skipEmpty: Bool = false) {
        self.mode = mode; self.csvColumn = csvColumn; self.csvHasHeader = csvHasHeader; self.skipEmpty = skipEmpty
    }
}

public enum BatchConverter {

    public static func convert(_ text: String, options: BatchOptions, transform: (String) -> String) -> String {
        switch options.mode {
        case .lines:
            return mapLines(text, skipEmpty: options.skipEmpty) { transform($0) }
        case .fileNames:
            return mapLines(text, skipEmpty: options.skipEmpty) { fileName($0, transform) }
        case .csvColumn:
            return csv(text, column: options.csvColumn, hasHeader: options.csvHasHeader, transform: transform)
        }
    }

    static func mapLines(_ text: String, skipEmpty: Bool, _ f: (String) -> String) -> String {
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let cr = raw.hasSuffix("\r")
            let line = cr ? String(raw.dropLast()) : raw
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !skipEmpty { out.append(raw) }
                continue
            }
            let lead = String(line.prefix { $0 == " " || $0 == "\t" })
            out.append(lead + f(line) + (cr ? "\r" : ""))
        }
        return out.joined(separator: "\n")
    }

    /// Converts the stem of a file name and keeps its extension and its separators (_ - . space).
    static func fileName(_ line: String, _ transform: (String) -> String) -> String {
        let name = line.trimmingCharacters(in: .whitespaces)
        var stem = name, ext = ""
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let e = name[name.index(after: dot)...]
            if (1...5).contains(e.count), e.allSatisfy({ $0.isLetter || $0.isNumber }) {
                stem = String(name[..<dot]); ext = "." + e
            }
        }
        // Words and separators.
        var words: [String] = [], seps: [String] = []
        var cur = "", sep = ""
        for c in stem {
            if c == "_" || c == "-" || c == " " || c == "." {
                if !cur.isEmpty { words.append(cur); seps.append(sep); cur = ""; sep = "" }
                sep.append(c)
            } else { cur.append(c) }
        }
        if !cur.isEmpty { words.append(cur); seps.append(sep); sep = "" }
        let trailing = sep
        guard !words.isEmpty else { return name }
        let converted = transform(words.joined(separator: " "))
        let newWords = converted.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard newWords.count == words.count else {
            return transform(stem) + ext
        }
        var out = ""
        for (i, w) in newWords.enumerated() { out += seps[i] + w }
        return out + trailing + ext
    }

    // MARK: CSV

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let counts: [(Character, Int)] = [(",", firstLine.filter { $0 == "," }.count),
                                          ("\t", firstLine.filter { $0 == "\t" }.count),
                                          (";", firstLine.filter { $0 == ";" }.count)]
        let best = counts.max { $0.1 < $1.1 }!
        return best.1 == 0 ? "," : best.0
    }

    /// RFC 4180 records. Returns the rows and the line ending used.
    static func parseCSV(_ text: String, delimiter d: Character) -> (rows: [[String]], newline: String, trailingNewline: Bool) {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false, fieldStarted = false
        var chars = Array(text)
        let trailing = text.hasSuffix("\n")
        if trailing { while chars.last == "\n" || chars.last == "\r" { chars.removeLast() } }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" && !fieldStarted {
                inQuotes = true; fieldStarted = true
            } else if c == d {
                row.append(field); field = ""; fieldStarted = false
            } else if c == "\r\n" || c == "\n" || c == "\r" {
                row.append(field); rows.append(row); row = []; field = ""; fieldStarted = false
            } else {
                field.append(c); fieldStarted = true
            }
            i += 1
        }
        if !chars.isEmpty { row.append(field); rows.append(row) }
        return (rows, newline, trailing)
    }

    static func writeField(_ f: String, delimiter d: Character) -> String {
        if f.contains(d) || f.contains("\"") || f.contains("\n") || f.contains("\r") {
            return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return f
    }

    static func csv(_ text: String, column: Int, hasHeader: Bool, transform: (String) -> String) -> String {
        let d = detectDelimiter(text)
        let parsed = parseCSV(text, delimiter: d)
        var rows = parsed.rows
        for r in rows.indices where !(hasHeader && r == 0) {
            guard column >= 0, column < rows[r].count else { continue }
            let v = rows[r][column]
            if !v.trimmingCharacters(in: .whitespaces).isEmpty { rows[r][column] = transform(v) }
        }
        let body = rows.map { $0.map { writeField($0, delimiter: d) }.joined(separator: String(d)) }.joined(separator: parsed.newline)
        return body + (parsed.trailingNewline ? parsed.newline : "")
    }

    /// Column names from the first row; empty names become "Column N".
    public static func csvColumns(_ text: String) -> [String] {
        csvColumns(text, hasHeader: true)
    }

    public static func csvColumns(_ text: String, hasHeader: Bool) -> [String] {
        let first = parseCSV(text, delimiter: detectDelimiter(text)).rows.first ?? []
        return first.enumerated().map { i, n in
            let t = n.trimmingCharacters(in: .whitespaces)
            return (!hasHeader || t.isEmpty) ? "Column \(i + 1)" : t
        }
    }
}
