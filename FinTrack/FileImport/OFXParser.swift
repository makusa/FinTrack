//
//  OFXParser.swift
//  FinTrack
//
//  Pure, dependency-free parser for OFX/QFX bank statements.
//  Handles BOTH 1.x SGML (unclosed leaf tags — the common bank case) and
//  2.x XML (closed tags), single-line payloads, XML entities, and the OFX
//  header's CHARSET (banks emit Windows-1252; accents break under UTF-8).
//
//  Output is provider-neutral and pre-normalization: amounts keep the file's
//  sign (− = debit). Mapping to IncomingBankTransaction happens downstream.
//

import Foundation

struct OFXTransaction: Equatable {
    var fitid: String
    var datePosted: Date
    var amount: Decimal       // signed as in the file (− = debit, + = credit)
    var name: String?         // <NAME>  — display payee
    var memo: String?         // <MEMO>
    var trnType: String?      // <TRNTYPE> (advisory only; sign is authoritative)
    var confidence: Int = 2   // 0=low,1=medium,2=high — PDF best-effort sets this; OFX/CSV are exact (2)
}

struct OFXStatement: Equatable {
    var bankId: String?       // <BANKID> (institution routing; for account fingerprint)
    var currency: String?     // <CURDEF>
    var accountId: String?    // <ACCTID> (informational; never stored in clear)
    var accountType: String?  // <ACCTTYPE> (CHECKING/SAVINGS/CREDITLINE/…)
    var transactions: [OFXTransaction]
    var source: String = "ofx"   // "ofx" | "csv" — namespace d externalId
    var ledgerBalance: Decimal? = nil   // <LEDGERBAL><BALAMT> — solde officiel déclaré par la banque
    var ledgerDate: Date? = nil         // <LEDGERBAL><DTASOF> — date de ce solde
}

enum OFXParseError: Error, Equatable {
    case notOFX
    case noTransactions
    case undecodable
}

enum OFXParser {

    // MARK: Entry points

    /// Parse raw bytes, honoring the OFX header CHARSET when present.
    static func parse(_ data: Data) throws -> OFXStatement {
        try parse(try decode(data))
    }

    /// Parse already-decoded OFX/QFX text.
    static func parse(_ raw: String) throws -> OFXStatement {
        guard let ofxRange = raw.range(of: "<OFX>") else { throw OFXParseError.notOFX }
        let body = String(raw[ofxRange.lowerBound...])

        // Put every tag on its own line so reading is uniform whether or not the
        // producer used newlines. Collapses the SGML/XML difference.
        let normalized = body.replacingOccurrences(of: "<", with: "\n<")

        var statement = OFXStatement(bankId: nil, currency: nil, accountId: nil,
                                     accountType: nil, transactions: [])
        var current: PartialTxn? = nil
        var inLedgerBal = false   // BALAMT/DTASOF existent aussi sous <AVAILBAL> — on ne
                                  // capte que ceux du bloc <LEDGERBAL> (solde officiel).

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.first == "<", let (tag, value) = Self.tagAndValue(line) else { continue }

            switch tag {
            case "BANKID":   if statement.bankId == nil      { statement.bankId = value.nilIfEmpty }
            case "CURDEF":   if statement.currency == nil    { statement.currency = value.nilIfEmpty }
            case "ACCTID":   if statement.accountId == nil    { statement.accountId = value.nilIfEmpty }
            case "ACCTTYPE": if statement.accountType == nil  { statement.accountType = value.nilIfEmpty }

            case "LEDGERBAL":  inLedgerBal = true
            case "/LEDGERBAL": inLedgerBal = false
            case "AVAILBAL":   inLedgerBal = false   // robustesse si /LEDGERBAL manquant
            case "BALAMT":
                if inLedgerBal, statement.ledgerBalance == nil {
                    statement.ledgerBalance = OFXAmount.parse(value)
                }
            case "DTASOF":
                if inLedgerBal, statement.ledgerDate == nil {
                    statement.ledgerDate = OFXDate.parse(value)
                }

            case "STMTTRN":  current = PartialTxn()
            case "/STMTTRN":
                if let txn = current?.build() { statement.transactions.append(txn) }
                current = nil

            case "TRNTYPE":  current?.trnType  = value.nilIfEmpty
            case "DTPOSTED": current?.dtposted = value
            case "TRNAMT":   current?.trnamt   = value
            case "FITID":    current?.fitid    = value
            case "NAME":     current?.name     = value.nilIfEmpty
            case "MEMO":     current?.memo     = value.nilIfEmpty

            default: break
            }
        }

        guard !statement.transactions.isEmpty else { throw OFXParseError.noTransactions }
        return statement
    }

    // MARK: Tokenizer

    /// From a line beginning with "<": return (UPPERCASE TAG, decoded trailing value).
    /// Handles "<TAG>value" (SGML), "<TAG>"/"</TAG>" (containers), and
    /// "<TAG>value</TAG>" (XML — trailing close stripped). Decodes XML entities.
    static func tagAndValue(_ line: String) -> (String, String)? {
        guard line.first == "<", let close = line.firstIndex(of: ">") else { return nil }
        let tag = String(line[line.index(after: line.startIndex)..<close]).uppercased()
        var value = String(line[line.index(after: close)...])
        if let lt = value.firstIndex(of: "<") { value = String(value[..<lt]) }   // XML close on same line
        value = Self.unescape(value.trimmingCharacters(in: .whitespacesAndNewlines))
        return (tag, value)
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&amp;",  with: "&")   // last, to avoid double-decoding
    }

    // MARK: Charset-aware decoding

    static func decode(_ data: Data) throws -> String {
        // 1) L'UTF-8 est auto-validant : si le fichier ENTIER se décode en UTF-8
        //    strict, c'est de l'UTF-8 — même si l'en-tête prétend CHARSET:1252
        //    (mensonge fréquent chez les banques). Un vrai fichier CP1252 avec
        //    accents (ex. é = 0xE9 isolé) échoue ici et tombe sur la voie 2.
        //    Les fichiers 100 % ASCII passent aussi ici (identiques en tout cas).
        if let s = String(data: data, encoding: .utf8) { return s }

        // 2) Pas de l'UTF-8 valide → charset mono-octet selon l'en-tête.
        let probe = String(decoding: data.prefix(256), as: UTF8.self).uppercased()
        let encoding: String.Encoding = probe.contains("8859-1") ? .isoLatin1 : .windowsCP1252
        if let s = String(data: data, encoding: encoding) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }   // single-byte: never fails
        throw OFXParseError.undecodable
    }
}

// MARK: - Internals

private struct PartialTxn {
    var fitid: String?
    var dtposted: String?
    var trnamt: String?
    var name: String?
    var memo: String?
    var trnType: String?

    func build() -> OFXTransaction? {
        guard let dtRaw = dtposted, let date = OFXDate.parse(dtRaw) else { return nil }
        guard let amtRaw = trnamt, let amount = OFXAmount.parse(amtRaw) else { return nil }
        let id = fitid?.nilIfEmpty ?? OFXAmount.fallbackId(date: date, amount: amount, name: name, memo: memo)
        return OFXTransaction(fitid: id, datePosted: date, amount: amount,
                              name: name, memo: memo, trnType: trnType)
    }
}

enum OFXDate {
    /// OFX datetime → Date from the leading YYYYMMDD (time/timezone dropped:
    /// banks post by calendar day). Anchored at local noon to avoid DST drift.
    static func parse(_ s: String) -> Date? {
        let digits = String(s.prefix { $0.isNumber })
        guard digits.count >= 8,
              let y = Int(digits.prefix(4)),
              let mo = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)),
              (1...12).contains(mo), (1...31).contains(d) else { return nil }
        var comp = DateComponents()
        comp.year = y; comp.month = mo; comp.day = d; comp.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        return cal.date(from: comp)
    }
}

enum OFXAmount {
    /// OFX uses '.' decimal, no grouping. Tolerant of a stray '+' and of a
    /// comma decimal from non-conformant producers.
    static func parse(_ s: String) -> Decimal? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("+") { t.removeFirst() }
        if t.contains(",") && !t.contains(".") {
            t = t.replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        return Decimal(string: t)
    }

    /// Stable (cross-launch) id for the rare case a producer omits FITID.
    /// FNV-1a over identifying fields — deterministic, so re-imports dedup
    /// (Swift's hashValue is per-launch randomized and would break dedup).
    static func fallbackId(date: Date, amount: Decimal, name: String?, memo: String?) -> String {
        let key = "\(Int(date.timeIntervalSince1970))|\(amount)|\(name ?? "")|\(memo ?? "")"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return "nofitid-" + String(hash, radix: 16)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
