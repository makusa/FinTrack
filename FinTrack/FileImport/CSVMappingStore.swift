//
//  CSVMappingStore.swift
//  FinTrack
//
//  Remembers the column mapping the user confirmed for a given CSV layout, keyed
//  by a hash of the (folded) header, so repeat imports from the same bank skip
//  the mapping step. Local (UserDefaults); stores no raw account data.
//

import Foundation
import CryptoKit

enum CSVMappingStore {
    private static let key = "fintrack.import.csvMappings_v1"

    static func remembered(forHeader header: [String]?, columnCount: Int) -> CSVColumnMapping? {
        let sig = signature(header: header, columnCount: columnCount)
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: CSVColumnMapping].self, from: data),
              let m = map[sig], indicesValid(m, columnCount: columnCount) else { return nil }
        return m
    }

    static func remember(_ mapping: CSVColumnMapping, forHeader header: [String]?, columnCount: Int) {
        let sig = signature(header: header, columnCount: columnCount)
        var map = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: CSVColumnMapping].self, from: $0) } ?? [:]
        map[sig] = mapping
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Stable key for a CSV layout: hash of the folded header, or a column-count
    /// sentinel when the file is headerless.
    static func signature(header: [String]?, columnCount: Int) -> String {
        guard let header = header, !header.isEmpty else { return "headerless:\(columnCount)" }
        let folded = header.map { CSVImporter.fold($0) }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(folded.utf8))
        return "h:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func indicesValid(_ m: CSVColumnMapping, columnCount: Int) -> Bool {
        func ok(_ i: Int?) -> Bool { i == nil || (i! >= 0 && i! < columnCount) }
        return ok(m.dateIndex) && ok(m.amountIndex) && ok(m.debitIndex) && ok(m.creditIndex)
            && m.descriptionIndices.allSatisfy { $0 >= 0 && $0 < columnCount }
            && m.dateIndex != nil && m.hasAmount
    }
}
