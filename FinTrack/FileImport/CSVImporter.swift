//
//  CSVImporter.swift
//  FinTrack
//
//  Pure, dependency-free CSV bank-statement parser. Unlike OFX/QFX there is no
//  standard: columns, date order, and sign convention vary per bank, and there
//  is no FITID. This auto-detects the column roles (date / amount or debit+credit
//  / description), normalizes dates (with dd/MM vs MM/dd disambiguation) and
//  amounts (FR/EN number formats), and emits the shared OFXStatement carrier
//  with source "csv". A stable per-row dedup seed stands in for the missing FITID.
//

import Foundation

// MARK: - Column mapping

struct CSVColumnMapping: Equatable, Codable {
    var dateIndex: Int?
    var amountIndex: Int?            // a single signed amount column …
    var debitIndex: Int?            // … OR a debit/credit pair (positive magnitudes)
    var creditIndex: Int?
    var descriptionIndices: [Int]
    var dateFormat: CSVDateFormat
    var dateOrderAssumed: Bool       // true → order defaulted; UI should confirm via an example

    var hasAmount: Bool { amountIndex != nil || debitIndex != nil || creditIndex != nil }
}

enum CSVDateFormat: String, Codable, Equatable {
    case iso          // yyyy-MM-dd / yyyy/MM/dd
    case dayFirst     // dd/MM/yyyy
    case monthFirst   // MM/dd/yyyy
    case compact      // yyyyMMdd
}

struct CSVParseResult {
    let header: [String]?            // nil when the file has no header row
    let rows: [[String]]            // data rows only (header excluded if present)
    let mapping: CSVColumnMapping
    let statement: OFXStatement
}

enum CSVImportError: Error, Equatable {
    case empty
    case noDateColumn
    case noAmountColumn
    case undecodable
}

enum CSVImporter {

    // MARK: Entry points

    static func parse(_ data: Data) throws -> CSVParseResult {
        try parse(try decode(data))
    }

    static func parse(_ text: String) throws -> CSVParseResult {
        let delimiter = detectDelimiter(text)
        let grid = tokenize(text, delimiter: delimiter).filter { row in
            !row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        guard !grid.isEmpty else { throw CSVImportError.empty }

        // The first row is a header unless it already looks like data (contains a
        // date-shaped cell) — then the file is headerless.
        let headerless = rowHasDate(grid[0])
        let header: [String]? = headerless ? nil : grid.first
        let rows = headerless ? grid : Array(grid.dropFirst())
        guard !rows.isEmpty else { throw CSVImportError.empty }

        let mapping = detectMapping(header: header, dataRows: rows)
        guard mapping.dateIndex != nil else { throw CSVImportError.noDateColumn }
        guard mapping.hasAmount else { throw CSVImportError.noAmountColumn }

        let statement = buildStatement(rows: rows, mapping: mapping, source: "csv")
        return CSVParseResult(header: header, rows: rows, mapping: mapping, statement: statement)
    }

    // MARK: Statement builder (re-used when the user corrects the mapping in the UI)

    static func buildStatement(rows: [[String]], mapping: CSVColumnMapping, source: String) -> OFXStatement {
        var txns: [OFXTransaction] = []
        var seen: [String: Int] = [:]
        for row in rows {
            guard let di = mapping.dateIndex, di < row.count,
                  let date = CSVDate.parse(row[di], format: mapping.dateFormat),
                  let amount = signedAmount(row: row, mapping: mapping) else { continue }
            let desc = mapping.descriptionIndices
                .compactMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            // No FITID in CSV: stable FNV-1a over date|amount|desc, plus an
            // occurrence index so identical same-day rows stay distinct while
            // re-imports of the same file remain idempotent.
            let key = "\(Int(date.timeIntervalSince1970))|\(amount)|\(desc.lowercased())"
            let occ = seen[key, default: 0]; seen[key] = occ + 1
            let fitid = "\(fnv1a(key))-\(occ)"
            txns.append(OFXTransaction(fitid: fitid, datePosted: date, amount: amount,
                                       name: desc.isEmpty ? nil : desc, memo: nil, trnType: nil))
        }
        return OFXStatement(bankId: nil, currency: nil, accountId: nil,
                            accountType: nil, transactions: txns, source: source)
    }

    // MARK: Tokenizer (RFC-4180-ish: quotes, escaped quotes, embedded newlines)

    static func tokenize(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    inQuotes = false; i += 1; continue
                }
                field.append(c); i += 1; continue
            }
            if c == "\"" { inQuotes = true; i += 1; continue }
            if c == delimiter { record.append(field); field = ""; i += 1; continue }
            if c == "\n" || c == "\r" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                record.append(field); field = ""
                rows.append(record); record = []
                i += 1; continue
            }
            field.append(c); i += 1
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); rows.append(record) }
        return rows
    }

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? text
        let candidates: [Character] = [",", ";", "\t"]
        var best: Character = ","; var bestCount = -1
        for d in candidates {
            let count = firstLine.filter { $0 == d }.count
            if count > bestCount { bestCount = count; best = d }
        }
        return best
    }

    static func decode(_ data: Data) throws -> String {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }   // UTF-8 BOM
        if let s = String(data: d, encoding: .utf8) { return s }
        if let s = String(data: d, encoding: .windowsCP1252) { return s }
        if let s = String(data: d, encoding: .isoLatin1) { return s }
        throw CSVImportError.undecodable
    }

    // MARK: Column detection

    static let dateKeywords   = ["date"]
    static let amountKeywords = ["amount", "montant"]
    static let debitKeywords  = ["debit", "retrait", "withdrawal", "depense"]
    static let creditKeywords = ["credit", "depot", "deposit", "encaissement"]
    static let descKeywords   = ["description", "libelle", "details", "narration",
                                 "payee", "beneficiaire", "merchant", "memo", "designation"]

    static func detectMapping(header: [String]?, dataRows: [[String]]) -> CSVColumnMapping {
        var dateIndex: Int?; var amountIndex: Int?
        var debitIndex: Int?; var creditIndex: Int?
        var descriptionIndices: [Int] = []

        if let header = header {
            for (idx, raw) in header.enumerated() {
                let h = fold(raw)
                if dateIndex == nil,   matches(h, dateKeywords)   { dateIndex = idx; continue }
                if debitIndex == nil,  matches(h, debitKeywords)  { debitIndex = idx; continue }
                if creditIndex == nil, matches(h, creditKeywords) { creditIndex = idx; continue }
                if amountIndex == nil, matches(h, amountKeywords) { amountIndex = idx; continue }
                if matches(h, descKeywords) { descriptionIndices.append(idx); continue }
            }
        }

        var excluded = Set([dateIndex, amountIndex, debitIndex, creditIndex].compactMap { $0 })
        if dateIndex == nil {
            dateIndex = sniffDateColumn(dataRows)
            if let d = dateIndex { excluded.insert(d) }
        }
        if amountIndex == nil && debitIndex == nil && creditIndex == nil {
            amountIndex = sniffAmountColumn(dataRows, excluding: excluded)
            if let a = amountIndex { excluded.insert(a) }
        }
        if descriptionIndices.isEmpty, let d = sniffDescriptionColumn(dataRows, excluding: excluded) {
            descriptionIndices = [d]
        }

        var fmt: CSVDateFormat = .iso; var assumed = false
        if let di = dateIndex {
            (fmt, assumed) = analyzeDateFormat(dataRows.compactMap { di < $0.count ? $0[di] : nil })
        }

        return CSVColumnMapping(dateIndex: dateIndex, amountIndex: amountIndex,
                                debitIndex: debitIndex, creditIndex: creditIndex,
                                descriptionIndices: descriptionIndices,
                                dateFormat: fmt, dateOrderAssumed: assumed)
    }

    static func matches(_ folded: String, _ keywords: [String]) -> Bool {
        keywords.contains { folded.contains($0) }
    }

    static func sniffDateColumn(_ rows: [[String]]) -> Int? {
        let cols = rows.map { $0.count }.max() ?? 0
        var best: Int?; var bestScore = 0
        for c in 0..<cols {
            let cells = rows.compactMap { c < $0.count ? $0[c] : nil }
            let hits = cells.filter { looksLikeDate($0) }.count
            if hits > bestScore && hits * 2 >= cells.count { bestScore = hits; best = c }
        }
        return best
    }

    static func sniffAmountColumn(_ rows: [[String]], excluding: Set<Int>) -> Int? {
        let cols = rows.map { $0.count }.max() ?? 0
        var best: Int?; var bestScore = 0
        for c in 0..<cols where !excluding.contains(c) {
            let cells = rows.compactMap { c < $0.count ? $0[c] : nil }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let hits = cells.filter { parseAmount($0) != nil }.count
            if hits > bestScore && hits * 2 >= cells.count { bestScore = hits; best = c }
        }
        return best
    }

    static func sniffDescriptionColumn(_ rows: [[String]], excluding: Set<Int>) -> Int? {
        let cols = rows.map { $0.count }.max() ?? 0
        var best: Int?; var bestScore = -1
        for c in 0..<cols where !excluding.contains(c) {
            let cells = rows.compactMap { c < $0.count ? $0[c] : nil }
            let text = cells.filter { parseAmount($0) == nil && !looksLikeDate($0) }
            let avg = text.isEmpty ? 0 : text.map { $0.count }.reduce(0, +) / text.count
            let score = text.count * 1000 + avg
            if score > bestScore { bestScore = score; best = c }
        }
        return best
    }

    // MARK: Dates

    static func looksLikeDate(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(whereSeparator: { "/-.".contains($0) })
        if parts.count == 3 && parts.allSatisfy({ $0.allSatisfy { $0.isNumber } }) { return true }
        if t.count == 8 && t.allSatisfy({ $0.isNumber }) { return true }
        return false
    }

    static func analyzeDateFormat(_ cells: [String]) -> (CSVDateFormat, Bool) {
        let samples = cells.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !samples.isEmpty else { return (.iso, false) }

        func parts(_ s: String) -> [String] { s.split(whereSeparator: { "/-.".contains($0) }).map(String.init) }

        let isoCount = samples.filter { let p = parts($0); return p.count == 3 && p[0].count == 4 }.count
        if isoCount * 2 >= samples.count { return (.iso, false) }

        let compactCount = samples.filter { $0.count == 8 && $0.allSatisfy { $0.isNumber } }.count
        if compactCount * 2 >= samples.count { return (.compact, false) }

        // Ambiguous A/B/yyyy: a first field > 12 ⇒ day-first; a second field > 12 ⇒ month-first.
        var firstGT12 = false, secondGT12 = false
        for s in samples {
            let p = parts(s)
            guard p.count == 3, let a = Int(p[0]), let b = Int(p[1]) else { continue }
            if a > 12 { firstGT12 = true }
            if b > 12 { secondGT12 = true }
        }
        if firstGT12 && !secondGT12 { return (.dayFirst, false) }
        if secondGT12 && !firstGT12 { return (.monthFirst, false) }
        return (.dayFirst, true)   // no/conflicting evidence → default day-first (FR/CA), confirm in UI
    }

    // MARK: Amounts

    static func signedAmount(row: [String], mapping: CSVColumnMapping) -> Decimal? {
        if let ai = mapping.amountIndex, ai < row.count { return parseAmount(row[ai]) }
        var result: Decimal?
        if let ci = mapping.creditIndex, ci < row.count, let c = parseAmount(row[ci]), c != 0 { result = abs(c) }
        if let dbi = mapping.debitIndex, dbi < row.count, let dv = parseAmount(row[dbi]), dv != 0 { result = -abs(dv) }
        return result
    }

    static let allowedAmountChars = Set("0123456789.,")

    /// Parse an amount across FR/EN conventions: "$1,234.56", "1 234,56",
    /// "1.234,56", "(12.34)" (negative), trailing "-", etc.
    static func parseAmount(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s.removeFirst(); s.removeLast() }
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }
        if s.hasSuffix("-") { negative = true; s.removeLast() }
        s = String(s.filter { allowedAmountChars.contains($0) })
        guard !s.isEmpty else { return nil }

        let hasComma = s.contains(","), hasDot = s.contains(".")
        if hasComma && hasDot {
            if s.lastIndex(of: ",")! > s.lastIndex(of: ".")! {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            let parts = s.components(separatedBy: ",")
            if parts.count == 2 && (1...2).contains(parts[1].count) {
                s = parts[0] + "." + parts[1]
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        }
        guard var value = Decimal(string: s) else { return nil }
        if negative { value.negate() }
        return value
    }

    // MARK: Helpers

    static func rowHasDate(_ row: [String]) -> Bool { row.contains { looksLikeDate($0) } }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
         .replacingOccurrences(of: "'", with: "")
         .replacingOccurrences(of: "\u{2019}", with: "")
         .trimmingCharacters(in: .whitespaces)
    }

    static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}

// MARK: - CSV date parsing

enum CSVDate {
    static func parse(_ raw: String, format: CSVDateFormat) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let comps: (y: Int, m: Int, d: Int)?
        switch format {
        case .iso:        comps = split(s, order: .ymd)
        case .dayFirst:   comps = split(s, order: .dmy)
        case .monthFirst: comps = split(s, order: .mdy)
        case .compact:    comps = compact(s)
        }
        guard let c = comps, (1...12).contains(c.m), (1...31).contains(c.d) else { return nil }
        var dc = DateComponents(); dc.year = c.y; dc.month = c.m; dc.day = c.d; dc.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        return cal.date(from: dc)
    }

    enum Order { case ymd, dmy, mdy }

    static func split(_ s: String, order: Order) -> (Int, Int, Int)? {
        let p = s.split(whereSeparator: { "/-.".contains($0) }).map(String.init)
        guard p.count == 3, let a = Int(p[0]), let b = Int(p[1]), let c = Int(p[2]) else { return nil }
        switch order {
        case .ymd: return (year(a), b, c)
        case .dmy: return (year(c), b, a)
        case .mdy: return (year(c), a, b)
        }
    }

    static func compact(_ s: String) -> (Int, Int, Int)? {
        let digits = s.filter { $0.isNumber }
        guard digits.count == 8, let y = Int(digits.prefix(4)),
              let m = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        return (y, m, d)
    }

    static func year(_ y: Int) -> Int { y < 100 ? 2000 + y : y }
}
