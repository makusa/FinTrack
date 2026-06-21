//
//  PDFStatementParser.swift
//  FinTrack
//
//  Best-effort, layout-agnostic parser for text extracted from a bank-statement
//  PDF. Bank PDF layouts change without notice, so we deliberately AVOID per-bank
//  templates. Instead, for each text line we: find a leading date (numeric or a
//  textual FR/EN month), find monetary amount(s) (requiring 2-digit cents so plain
//  reference numbers are ignored), drop a trailing running-balance column when
//  present, infer the sign from explicit markers (−, parentheses, CR/DR) or a
//  description keyword (dépôt/salaire/…), and attach a confidence score. Shaky rows
//  (e.g. an unsigned amount defaulted to an expense) come back LOW so the mandatory
//  review screen can pre-uncheck them. Over-capture is safer than silent omission.
//

import Foundation

enum PDFParseError: Error, Equatable {
    case noTransactions
}

enum PDFStatementParser {

    // MARK: Entry points

    static func parse(text: String, referenceYear: Int? = nil) throws -> OFXStatement {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        return try parse(lines: lines, referenceYear: referenceYear)
    }

    static func parse(lines rawLines: [String], referenceYear: Int? = nil) throws -> OFXStatement {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }
        let year = referenceYear ?? detectStatementYear(lines)
            ?? Calendar.current.component(.year, from: Date())

        var txns: [OFXTransaction] = []
        var seen: [String: Int] = [:]
        for line in lines where !line.isEmpty {
            guard let r = parseLine(line, year: year) else { continue }
            let key = "\(Int(r.date.timeIntervalSince1970))|\(r.amount)|\(r.description.lowercased())"
            let occ = seen[key, default: 0]; seen[key] = occ + 1
            txns.append(OFXTransaction(
                fitid: "\(fnv1a(key))-\(occ)", datePosted: r.date, amount: r.amount,
                name: r.description.isEmpty ? nil : r.description,
                memo: nil, trnType: nil, confidence: r.confidence.rawValue))
        }
        guard !txns.isEmpty else { throw PDFParseError.noTransactions }
        return OFXStatement(bankId: nil, currency: nil, accountId: nil,
                            accountType: nil, transactions: txns, source: "pdf")
    }

    // MARK: Per-line parsing

    enum PDFConfidence: Int, Comparable {
        case low = 0, medium = 1, high = 2
        static func < (l: PDFConfidence, r: PDFConfidence) -> Bool { l.rawValue < r.rawValue }
    }

    struct LineResult {
        let date: Date
        let amount: Decimal        // signed
        let description: String
        let confidence: PDFConfidence
    }

    static func parseLine(_ line: String, year: Int) -> LineResult? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }).map(String.init)
        guard tokens.count >= 2 else { return nil }

        guard let (date, consumed, dateCertain) = parseLeadingDate(tokens, referenceYear: year) else { return nil }
        let remainder = tokens.dropFirst(consumed).joined(separator: " ")
        guard !remainder.isEmpty else { return nil }

        let matches = moneyMatches(in: remainder)
        guard let chosen = matches.first else { return nil }
        let usedBalanceHeuristic = matches.count >= 2

        // Description = remainder minus every money substring (removed back-to-front
        // so earlier NSRanges stay valid).
        var desc = remainder
        for m in matches.reversed() {
            if let range = Range(m.range, in: desc) { desc.removeSubrange(range) }
        }
        desc = collapseSpaces(desc).trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—|:."))
        if isNoiseDescription(desc) { return nil }

        let (signed, signConf) = resolveSign(magnitude: chosen.value, token: chosen.raw, description: desc)

        var conf = PDFConfidence.high
        if !dateCertain { conf = min(conf, .medium) }
        if usedBalanceHeuristic { conf = min(conf, .medium) }
        conf = min(conf, signConf)

        return LineResult(date: date, amount: signed, description: desc, confidence: conf)
    }

    // MARK: Dates

    static func parseLeadingDate(_ tokens: [String], referenceYear: Int) -> (date: Date, consumed: Int, certain: Bool)? {
        guard let first = tokens.first else { return nil }

        // A) Single numeric token (ISO or d/m/y).
        if let (d, certain) = parseNumericDate(first, referenceYear: referenceYear) {
            return (d, 1, certain)
        }
        // B1) "DD Month [YYYY]"
        if tokens.count >= 2, let day = Int(digits(tokens[0])), (1...31).contains(day),
           let month = monthNumber(tokens[1]) {
            if tokens.count >= 3, let y = parseYear(tokens[2]), let date = makeDate(y, month, day) {
                return (date, 3, true)
            }
            if let date = makeDate(referenceYear, month, day) { return (date, 2, false) }
        }
        // B2) "Month DD[,] [YYYY]"
        if tokens.count >= 2, let month = monthNumber(tokens[0]),
           let day = Int(digits(tokens[1])), (1...31).contains(day) {
            if tokens.count >= 3, let y = parseYear(tokens[2]), let date = makeDate(y, month, day) {
                return (date, 3, true)
            }
            if let date = makeDate(referenceYear, month, day) { return (date, 2, false) }
        }
        return nil
    }

    static func parseNumericDate(_ token: String, referenceYear: Int) -> (Date, Bool)? {
        let parts = token.split(whereSeparator: { "/-.".contains($0) }).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        if parts[0].count == 4 { return makeDate(a, b, c).map { ($0, true) } }   // ISO
        let year = parts[2].count >= 4 ? c : 2000 + c
        if a > 12, (1...12).contains(b) { return makeDate(year, b, a).map { ($0, true) } }    // day-first, certain
        if b > 12, (1...12).contains(a) { return makeDate(year, a, b).map { ($0, false) } }   // month-first
        return makeDate(year, b, a).map { ($0, false) }                                       // default day-first
    }

    static let monthMap: [String: Int] = {
        var m: [String: Int] = [:]
        let fr = ["janvier","fevrier","mars","avril","mai","juin","juillet","aout","septembre","octobre","novembre","decembre"]
        let en = ["january","february","march","april","may","june","july","august","september","october","november","december"]
        for (i, n) in fr.enumerated() { m[n] = i + 1; m[String(n.prefix(3))] = i + 1 }
        for (i, n) in en.enumerated() { m[n] = i + 1; m[String(n.prefix(3))] = i + 1 }
        for (k, v) in ["janv": 1, "fev": 2, "fevr": 2, "avr": 4, "juin": 6, "juil": 7, "juill": 7,
                       "sept": 9, "oct": 10, "nov": 11, "dec": 12] { m[k] = v }
        return m
    }()

    static func monthNumber(_ token: String) -> Int? {
        let t = fold(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if let n = monthMap[t] { return n }
        if t.count >= 3, let n = monthMap[String(t.prefix(3))] { return n }
        return nil
    }

    static func parseYear(_ token: String) -> Int? {
        let t = digits(token)
        guard let n = Int(t) else { return nil }
        if t.count == 4, (1990...2100).contains(n) { return n }
        if t.count == 2 { return 2000 + n }
        return nil
    }

    static func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        var dc = DateComponents(); dc.year = y; dc.month = m; dc.day = d; dc.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        return cal.date(from: dc)
    }

    static func detectStatementYear(_ lines: [String]) -> Int? {
        let head = lines.prefix(20).joined(separator: " ")
        let ns = head as NSString
        let re = try! NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)
        let years = re.matches(in: head, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range)) }
            .filter { (1990...2100).contains($0) }
        guard !years.isEmpty else { return nil }
        let counts = Dictionary(grouping: years, by: { $0 }).mapValues(\.count)
        return counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key
    }

    // MARK: Amounts

    struct MoneyMatch { let raw: String; let value: Decimal; let range: NSRange }

    // Sign/$, integer with optional grouping, then a decimal with exactly 2 cents
    // (so plain ref numbers like "12345" never match), optional ) and CR/DR.
    static let moneyRegex = try! NSRegularExpression(
        pattern: #"[-+(]?\s*\$?\s*\d{1,3}(?:[ \u00A0.,]\d{3})*[.,]\d{2}\)?(?:\s?(?:CR|DR)\b)?"#,
        options: [.caseInsensitive])

    static func moneyMatches(in s: String) -> [MoneyMatch] {
        let ns = s as NSString
        return moneyRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let raw = ns.substring(with: m.range)
            guard let v = parseMoney(raw) else { return nil }
            return MoneyMatch(raw: raw, value: v, range: m.range)
        }
    }

    static let moneyChars = Set("0123456789.,")

    /// Magnitude (always positive); the sign is decided separately from markers.
    static func parseMoney(_ raw: String) -> Decimal? {
        var s = String(raw.uppercased().filter { moneyChars.contains($0) })
        guard !s.isEmpty else { return nil }
        let hasComma = s.contains(","), hasDot = s.contains(".")
        if hasComma && hasDot {
            if s.lastIndex(of: ",")! > s.lastIndex(of: ".")! {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            s = s.replacingOccurrences(of: ",", with: ".")   // regex guarantees 2-digit cents → comma is decimal
        }
        return Decimal(string: s).map { abs($0) }
    }

    // Income cues in the description, word-bounded so "paie" never matches
    // "paiement". "credit" is intentionally absent — in a description it usually
    // means "credit card", not a deposit; real credits carry an explicit CR marker.
    static let incomeRegex = try! NSRegularExpression(
        pattern: #"\b(?:depots?|deposits?|salaires?|paies?|payes?|virements?\s+recus?|transferts?\s+recus?|remboursements?|interets?|interest|dividendes?|rentes?)\b"#,
        options: [.caseInsensitive])

    static func resolveSign(magnitude: Decimal, token: String, description: String) -> (Decimal, PDFConfidence) {
        let t = token.uppercased()
        if t.contains("(") || t.contains("-") { return (-magnitude, .high) }
        if t.contains("CR") { return (magnitude, .high) }
        if t.contains("DR") { return (-magnitude, .high) }
        if t.contains("+") { return (magnitude, .high) }
        let d = fold(description)
        if incomeRegex.firstMatch(in: d, range: NSRange(location: 0, length: (d as NSString).length)) != nil {
            return (magnitude, .medium)
        }
        return (-magnitude, .low)   // best-effort default: expense
    }

    // MARK: Noise

    static let noiseKeywords = ["solde", "balance", "total", "sous-total", "subtotal"]

    static func isNoiseDescription(_ desc: String) -> Bool {
        let d = fold(desc)
        if d.isEmpty { return true }   // date + amount with no payee → likely a balance line
        return noiseKeywords.contains { d.contains($0) }
    }

    // MARK: Helpers

    static func digits(_ s: String) -> String { String(s.filter(\.isNumber)) }

    static func collapseSpaces(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }).joined(separator: " ")
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")).lowercased()
    }

    static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
