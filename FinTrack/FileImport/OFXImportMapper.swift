//
//  OFXImportMapper.swift
//  FinTrack
//
//  Maps a parsed OFX/QFX statement onto the provider-neutral
//  IncomingBankTransaction rows consumed by TransactionReconciler.
//  One statement targets exactly one FinTrack account (chosen upstream).
//

import Foundation

enum OFXImportMapper {

    /// Map every transaction of `statement` onto a reconciler row targeting
    /// `accountUuid`. externalId is namespaced by account because FITID is only
    /// unique within an account.
    static func map(statement: OFXStatement, accountUuid: String) -> [IncomingBankTransaction] {
        statement.transactions.map { t in
            IncomingBankTransaction(
                externalId: "ofx:\(accountUuid):\(t.fitid)",
                accountKey: accountUuid,
                isIncome: t.amount > 0,
                amount: abs(t.amount),
                date: t.datePosted,
                payee: t.name,
                note: t.memo ?? "",
                bankDescription: bankDescription(name: t.name, memo: t.memo)
            )
        }
    }

    /// Preserve the raw bank wording on the row: NAME + MEMO when both present.
    static func bankDescription(name: String?, memo: String?) -> String? {
        let n = (name?.isEmpty == false) ? name : nil
        let m = (memo?.isEmpty == false) ? memo : nil
        switch (n, m) {
        case let (n?, m?): return "\(n) — \(m)"
        case let (n?, nil): return n
        case let (nil, m?): return m
        case (nil, nil):    return nil
        }
    }
}
