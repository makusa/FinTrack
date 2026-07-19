//
//  PDFStatementParser.swift
//  FinTrack
//
//  Best-effort, layout-agnostic parser for text extracted from a bank-statement
//  PDF. Bank PDF layouts change without notice, so we deliberately AVOID per-bank
//  templates. Instead: (1) each line gets a leading date (numeric or textual FR/EN
//  month), or inherits the current day-group date (banks print the date only on
//  the first row of a day); (2) monetary amounts require 2-digit cents and can't
//  start glued to a digit (reference numbers stay out); (3) balance lines (Solde
//  d'ouverture / running balance column / Solde de clôture) become CHECKPOINTS,
//  and between two checkpoints the unique sign assignment satisfying
//  Σ ± amounts = Δbalance PROVES the signs — falling back to explicit markers
//  (−, parentheses, CR/DR) or description keywords when arithmetic can't decide;
//  (4) the closing balance feeds OFXStatement.ledgerBalance so the post-import
//  balance check works for PDFs too. Shaky rows come back LOW so the mandatory
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

        // ── Passe 1 : classer chaque ligne en « point de solde » (Solde d'ouverture,
        // solde courant en fin de rangée, Solde de clôture…) ou « transaction »
        // (datée, ou héritant de la date du groupe de jour courant — les banques
        // n'impriment souvent la date que sur la première ligne du jour).
        enum Event {
            case checkpoint(value: Decimal, closing: Bool)
            case row(Row)
        }
        struct Row {
            let date: Date
            let dateCertain: Bool
            let carriedDate: Bool
            let amount: Decimal
            let amountToken: String
            let hadTrailingBalance: Bool
            let desc: String
        }
        var events: [Event] = []
        var carryDate: Date? = nil
        var carryCertain = false
        var lastRowIndex: Int? = nil   // pour rattacher une ligne de description
        var appendBudget = 0           // 1 ligne de continuation max par transaction

        for line in lines where !line.isEmpty {
            // Point de solde : ligne « solde/balance » — la DERNIÈRE valeur
            // monétaire est le solde. Un solde de clôture termine le tableau
            // (stoppe l'héritage de date pour ignorer les pages légales).
            if isBalanceCheckpoint(line), let last = moneyMatches(in: line).last {
                let closing = isClosingBalance(line)
                events.append(.checkpoint(value: checkpointValue(last), closing: closing))
                if closing { carryDate = nil; lastRowIndex = nil }
                continue
            }

            let tokens = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" || $0 == "\u{202F}" })
                .map(String.init)
            guard tokens.count >= 2 else { continue }

            let date: Date, consumed: Int, certain: Bool, carried: Bool
            if let d = parseLeadingDate(tokens, referenceYear: year) {
                (date, consumed, certain) = d; carried = false
                carryDate = d.date; carryCertain = d.certain
            } else if let c = carryDate {
                (date, consumed, certain, carried) = (c, 0, carryCertain, true)
            } else { continue }

            let remainder = tokens.dropFirst(consumed).joined(separator: " ")
            guard !remainder.isEmpty else { continue }
            let matches = moneyMatches(in: remainder)
            guard let first = matches.first else {
                // Ligne SANS montant : suite de la description de la transaction
                // précédente (les banques coupent souvent le libellé sur 2 lignes).
                if carried, appendBudget > 0, let idx = lastRowIndex,
                   case .row(let prev) = events[idx],
                   tokens.count <= 8, !isNoiseDescription(remainder),
                   !fold(remainder).contains("page") {
                    events[idx] = .row(Row(date: prev.date, dateCertain: prev.dateCertain,
                                           carriedDate: prev.carriedDate,
                                           amount: prev.amount, amountToken: prev.amountToken,
                                           hadTrailingBalance: prev.hadTrailingBalance,
                                           desc: prev.desc + " " + collapseSpaces(remainder)))
                    appendBudget = 0
                }
                continue
            }
            guard first.value != 0 else { continue }   // 0,00 : jamais une transaction

            var desc = remainder
            for m in matches.reversed() {
                if let range = Range(m.range, in: desc) { desc.removeSubrange(range) }
            }
            desc = collapseSpaces(desc).trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—|:."))
            if isNoiseDescription(desc) { continue }

            events.append(.row(Row(date: date, dateCertain: certain, carriedDate: carried,
                                   amount: first.value, amountToken: first.raw,
                                   hadTrailingBalance: matches.count >= 2, desc: desc)))
            lastRowIndex = events.count - 1
            appendBudget = 1
            // Solde courant en fin de rangée = point de solde APRÈS cette ligne.
            if matches.count >= 2, let last = matches.last {
                events.append(.checkpoint(value: checkpointValue(last), closing: false))
            }
        }

        // ── Passe 2 : entre deux points de solde, l'arithmétique de la banque
        // impose les signes (Σ ± montants = ΔSolde). Solution unique → signes
        // prouvés (.high). Sinon, repli sur l'heuristique marqueurs/mots-clés.
        struct Signed { let date: Date; let amount: Decimal; let desc: String; let conf: PDFConfidence }
        var results: [Signed] = []
        var ledgerBalance: Decimal? = nil

        func heuristic(_ r: Row) -> Signed {
            let (signed, signConf) = resolveSign(magnitude: r.amount, token: r.amountToken, description: r.desc)
            var conf = PDFConfidence.high
            if !r.dateCertain || r.carriedDate { conf = min(conf, .medium) }
            if r.hadTrailingBalance { conf = min(conf, .medium) }
            conf = min(conf, signConf)
            return Signed(date: r.date, amount: signed, desc: r.desc, conf: conf)
        }

        var pending: [Row] = []
        var lastCheckpoint: Decimal? = nil
        for ev in events {
            switch ev {
            case .row(let r):
                pending.append(r)
            case .checkpoint(let value, let closing):
                if let b0 = lastCheckpoint, !pending.isEmpty,
                   let signs = solveSigns(pending.map(\.amount), delta: value - b0) {
                    for (r, positive) in zip(pending, signs) {
                        results.append(Signed(date: r.date,
                                              amount: positive ? r.amount : -r.amount,
                                              desc: r.desc, conf: .high))
                    }
                } else {
                    pending.forEach { results.append(heuristic($0)) }
                }
                pending = []
                lastCheckpoint = value
                if closing { ledgerBalance = value }
            }
        }
        pending.forEach { results.append(heuristic($0)) }

        guard !results.isEmpty else { throw PDFParseError.noTransactions }

        var txns: [OFXTransaction] = []
        var seen: [String: Int] = [:]
        for r in results {
            let key = "\(Int(r.date.timeIntervalSince1970))|\(r.amount)|\(r.desc.lowercased())"
            let occ = seen[key, default: 0]; seen[key] = occ + 1
            txns.append(OFXTransaction(
                fitid: "\(fnv1a(key))-\(occ)", datePosted: r.date, amount: r.amount,
                name: r.desc.isEmpty ? nil : r.desc,
                memo: nil, trnType: nil, confidence: r.conf.rawValue))
        }

        var st = OFXStatement(bankId: nil, currency: nil, accountId: nil,
                              accountType: nil, transactions: txns, source: "pdf")
        st.ledgerBalance = ledgerBalance
        if ledgerBalance != nil {
            st.ledgerDate = detectPeriodEndDate(lines, referenceYear: year)
                ?? results.map(\.date).max()
        }
        return st
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
        // « jui » : la boucle ci-dessus l'écrase avec juillet (prefix(3)) ; or les
        // banques (ex. Scotia) l'utilisent pour JUIN — juillet s'abrège « juil ».
        for (k, v) in ["janv": 1, "fev": 2, "fevr": 2, "avr": 4, "jui": 6, "juin": 6, "juil": 7, "juill": 7,
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
        let head = lines.prefix(40).joined(separator: " ")
        let ns = head as NSString
        let re = try! NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)
        let years = re.matches(in: head, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range)) }
            .filter { (1990...2100).contains($0) }
        guard !years.isEmpty else { return nil }
        let counts = Dictionary(grouping: years, by: { $0 }).mapValues(\.count)
        return counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key
    }

    /// Date la plus tardive écrite EN TOUTES LETTRES avec année explicite dans
    /// l'en-tête (ex. « Du 1 mai 2026 au 3 juin 2026 » → 3 juin 2026). Sert de
    /// date au solde de clôture.
    static func detectPeriodEndDate(_ lines: [String], referenceYear: Int) -> Date? {
        var best: Date? = nil
        for line in lines.prefix(40) {
            let tokens = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" || $0 == "\u{202F}" })
                .map(String.init)
            guard tokens.count >= 2 else { continue }
            for i in 0..<tokens.count {
                if let (d, _, certain) = parseLeadingDate(Array(tokens[i...]), referenceYear: referenceYear),
                   certain, best.map({ d > $0 }) ?? true {
                    best = d
                }
            }
        }
        return best
    }

    // MARK: Points de solde (checkpoints)

    static let closingKeywords = ["cloture", "fermeture", "closing", "new balance", "solde final", "ending balance"]

    /// Ligne « solde/balance » portant une valeur : point de contrôle du solde
    /// courant. « total » est exclu (lignes de sommaire, pas des soldes).
    static func isBalanceCheckpoint(_ line: String) -> Bool {
        let d = fold(line)
        guard d.contains("solde") || d.contains("balance") else { return false }
        return !d.contains("total")
    }

    static func isClosingBalance(_ line: String) -> Bool {
        let d = fold(line)
        return closingKeywords.contains { d.contains($0) }
    }

    /// Valeur signée d'un point de solde (les relevés de cartes impriment des
    /// soldes négatifs ou suffixés DR).
    static func checkpointValue(_ m: MoneyMatch) -> Decimal {
        let t = m.raw.uppercased()
        if t.contains("(") || t.contains("-") || t.contains("DR") { return -m.value }
        return m.value
    }

    /// Entre deux soldes B0 → B1 avec des montants non signés a1…an, cherche
    /// l'UNIQUE affectation de signes telle que Σ ±ai = B1 − B0. Retourne nil si
    /// aucune ou plusieurs solutions (repli heuristique). n ≤ 12 (force brute).
    static func solveSigns(_ magnitudes: [Decimal], delta: Decimal) -> [Bool]? {
        let n = magnitudes.count
        guard n > 0, n <= 12 else { return nil }
        let epsilon = Decimal(string: "0.005")!
        var solution: [Bool]? = nil
        for mask in 0..<(1 << n) {
            var sum = Decimal(0)
            for i in 0..<n {
                sum += (mask & (1 << i)) != 0 ? magnitudes[i] : -magnitudes[i]
            }
            if abs(sum - delta) < epsilon {
                if solution != nil { return nil }   // ambigu
                solution = (0..<n).map { (mask & (1 << $0)) != 0 }
            }
        }
        return solution
    }

    // MARK: Amounts

    struct MoneyMatch { let raw: String; let value: Decimal; let range: NSRange }

    // Sign/$, integer with grouping CONSISTENT with the decimal style, then exactly
    // 2-digit cents (plain ref numbers never match), optional trailing -, ) or CR/DR.
    // Trois styles : « 9 241,25 » (FR : espaces + virgule), « 9,241.25 » (EN :
    // virgules + point), « 9.241,25 » (EU) — ou sans groupement. Un style mixte
    // comme « NO. 9 241.25 » (nº de chèque puis montant) ne matche donc plus d'un
    // bloc. Lookbehind : un montant ne peut pas commencer collé à un chiffre —
    // sinon « dépôt-0980 357,00 » matchait « 980 357,00 » (référence avalée).
    // Le « - » traînant (« 6.30- ») est le format négatif de certaines banques.
    static let moneyRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9.,])[-+(]?\s*\$?\s*(?:\d{1,3}(?:[ \u00A0\u202F]\d{3})+,\d{2}|\d{1,3}(?:,\d{3})+\.\d{2}|\d{1,3}(?:\.\d{3})+,\d{2}|\d+[.,]\d{2})-?\)?(?:\s?(?:CR|DR)\b)?"#,
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
    // « compte de dépôt » est exclu : « Télévirement au compte de dépôt-1234 » est
    // un RETRAIT (télévirement sortant), pas un dépôt.
    static let incomeRegex = try! NSRegularExpression(
        pattern: #"\b(?:(?<!compte\sde\s)depots?|deposits?|salaires?|paies?|payes?|virements?\s+recus?|transferts?\s+recus?|remboursements?|interets?|interest|dividendes?|rentes?)\b"#,
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
        if !d.contains(where: \.isLetter) { return true }   // « = = », refs nus → bruit
        return noiseKeywords.contains { d.contains($0) }
    }

    // MARK: Helpers

    static func digits(_ s: String) -> String { String(s.filter(\.isNumber)) }

    static func collapseSpaces(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" || $0 == "\u{202F}" }).joined(separator: " ")
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
