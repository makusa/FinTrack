//
//  PayeeNormalizer.swift
//  FinTrack
//
//  Turns a raw bank-statement payee/description into a stable, comparable key for
//  categorization, merchant memory, and dedup. Bank labels are noisy: processor
//  prefixes ("PAYPAL *SPOTIFY"), banking prefixes ("PAIEMENT PRÉAUTORISÉ …",
//  "MB-…", "PC FROM …"), store/reference numbers, card numbers, and trailing
//  province/country codes. We strip all of it down to the distinctive words.
//
//  Security note: ALL digit runs are removed, so card numbers (PANs) that some
//  banks leak into descriptions never survive into a stored key.
//

import Foundation

enum PayeeNormalizer {

    /// Banking/order prefixes to drop from the FRONT (folded, uppercased, multi-word
    /// entries first). INTERAC is intentionally kept — "INTERAC E TRANSFER" is a
    /// more distinctive memory key than a bare "E TRANSFER".
    static let leadingPrefixes: [[String]] = [
        ["PAIEMENT", "PREAUTORISE"], ["PRE", "AUTORISE"], ["PC", "FROM"], ["VISA", "DEBIT"],
        ["PAIEMENT"], ["ACHAT"], ["ACH"], ["POS"], ["RETRAIT"], ["DEPOT"],
        ["VISA"], ["DEBIT"], ["PREAUTORISE"], ["TRANSFERT"], ["VIREMENT"],
        ["FREE"], ["MB"],
        // payment-processor codes ("PAYPAL *SPOTIFY", "SQ *CAFE", "TST* …")
        ["PAYPAL"], ["PYPL"], ["SQ"], ["SQUARE"], ["TST"], ["SP"]
    ].sorted { $0.count > $1.count }

    /// Trailing geographic tokens to drop from the END.
    static let geoSuffixes: Set<String> = [
        "QC", "ON", "BC", "AB", "MB", "SK", "NS", "NB", "PE", "NL", "YT", "NT", "NU",
        "CA", "US", "USA"   // "CANADA"/"CAN" volontairement absents (cf. "Air Canada")
    ]

    static func normalize(_ raw: String) -> String {
        // 1) Fold accents + uppercase.
        let s = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                            locale: Locale(identifier: "en")).uppercased()

        // 2) Letters/spaces only; digits and punctuation (incl. '*') become
        //    separators (this is where card/reference numbers are erased).
        var cleaned = ""
        for ch in s {
            cleaned.append(ch.isLetter ? ch : " ")
        }

        var tokens = cleaned.split(separator: " ").map(String.init)

        // 3) Strip leading prefixes (iteratively, never emptying the token list).
        tokens = stripLeadingPrefixes(tokens)

        // 4) Strip trailing geo tokens.
        while let last = tokens.last, geoSuffixes.contains(last) { tokens.removeLast() }

        return tokens.joined(separator: " ")
    }

    static func stripLeadingPrefixes(_ tokens: [String]) -> [String] {
        var t = tokens
        var changed = true
        while changed {
            changed = false
            // >= so a label that is ONLY prefixes (e.g. "PC FROM <card#>" after digit
            // stripping) collapses to empty — a contentless transfer, correctly uncategorized.
            for p in leadingPrefixes where t.count >= p.count && Array(t.prefix(p.count)) == p {
                t.removeFirst(p.count)
                changed = true
                break
            }
        }
        return t
    }
}
