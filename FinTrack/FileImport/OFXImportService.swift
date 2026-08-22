//
//  OFXImportService.swift
//  FinTrack
//
//  App-facing glue for OFX/QFX import: account suggestion + commit through the
//  shared reconciliation pipeline, then remember the account mapping.
//

import Foundation
import SwiftData

enum OFXImportService {

    /// Suggest the destination account for a parsed statement.
    static func suggestAccount(for statement: OFXStatement,
                               among accounts: [Account]) -> AccountSuggestion {
        let descriptors = accounts.map {
            ImportAccountDescriptor(uuid: $0.uuid, currency: $0.currency, typeRaw: $0.typeRaw)
        }
        return OFXAccountMatcher.suggest(statement: statement,
                                         accounts: descriptors,
                                         remembered: ImportAccountMap.remembered())
    }

    /// Map the (already user-confirmed) statement onto the chosen account and run
    /// it through TransactionReconciler. Records the account mapping on success.
    @discardableResult
    static func commit(statement: OFXStatement,
                       into account: Account,
                       context: ModelContext,
                       categories: [String: Category] = [:]) -> TransactionReconciler.Outcome {
        let rows = OFXImportMapper.map(statement: statement, accountUuid: account.uuid, categories: categories)
        let outcome = TransactionReconciler.reconcile(rows, context: context)
        ImportAccountMap.record(
            fingerprint: ImportAccountMap.fingerprint(bankId: statement.bankId, acctId: statement.accountId),
            accountUuid: account.uuid
        )
        return outcome
    }

    // MARK: - Virements marqués à l'import

    /// Commit des lignes marquées « virement » pendant la vérification.
    /// Pour chaque ligne : dédup par externalId ; sinon adoption d'une jambe de
    /// virement manuelle correspondante (même compte, même sens, même montant,
    /// fenêtre du TransactionMatcher) ; sinon création des deux jambes liées
    /// par transferPairId (même devise uniquement — décidé en amont par l'UI).
    /// La jambe importée est bank-backed (externalId + .reconciled) ; la
    /// contrepartie reste sans externalId (.cleared) pour être adoptée quand
    /// le relevé de l'autre compte sera importé.
    static func commitTransfers(_ items: [(txn: OFXTransaction, counterpart: Account)],
                                statement: OFXStatement,
                                into account: Account,
                                context: ModelContext,
                                toLabel: String,
                                fromLabel: String) -> (added: Int, adopted: Int, skipped: Int) {
        guard !items.isEmpty else { return (0, 0, 0) }

        let existing = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        var knownIds = Set(existing.compactMap { $0.externalId })

        // Candidats à l'adoption : jambes de virement manuelles du compte importé.
        var pool = existing.filter {
            $0.externalId == nil && $0.status != .skipped
                && $0.transferPairId != nil && $0.account?.uuid == account.uuid
        }

        var added = 0, adopted = 0, skipped = 0
        var touched: Set<PersistentIdentifier> = [account.persistentModelID]

        for (t, counterpart) in items {
            let externalId = "\(statement.source):\(account.uuid):\(t.fitid)"
            guard !knownIds.contains(externalId) else { skipped += 1; continue }
            knownIds.insert(externalId)

            let isOutgoing = t.amount < 0   // sortant : dépense ici, revenu chez la contrepartie
            let amount = abs(t.amount)

            // Adoption d'une jambe de virement manuelle existante.
            let candidates = pool.enumerated().map { (i, m) in
                MatchCandidate(id: "\(i)", accountKey: account.uuid,
                               isIncome: m.type == .income, amount: m.amount, date: m.date)
            }
            let decision = TransactionMatcher.decide(
                incomingAccountKey: account.uuid,
                incomingIsIncome: !isOutgoing,
                incomingAmount: amount,
                incomingDate: t.datePosted,
                candidates: candidates
            )
            // .review = plusieurs jambes plausibles ; le pool est déjà restreint aux
            // virements de même sens/montant à ±4 jours — on adopte la plus proche.
            let adoptedId: String? = {
                switch decision {
                case .autoLink(let id):  return id
                case .review(let ids):   return ids.first
                case .insertNew:         return nil
                }
            }()
            if let id = adoptedId, let idx = Int(id), pool.indices.contains(idx) {
                let manual = pool[idx]
                manual.externalId = externalId
                manual.bankDescription = OFXImportMapper.bankDescription(name: t.name, memo: t.memo)
                manual.status = .reconciled
                if let a = manual.account { touched.insert(a.persistentModelID) }
                pool.remove(at: idx)
                adopted += 1
                continue
            }

            // Création des deux jambes (patron AddTransferView, même devise).
            let pairId = UUID()
            let defaultNote = isOutgoing ? "\(toLabel) \(counterpart.name)" : "\(fromLabel) \(counterpart.name)"
            let importedNote: String = {
                if let m = t.memo, !m.isEmpty { return m }
                return defaultNote
            }()
            let counterpartNote = isOutgoing ? "\(fromLabel) \(account.name)" : "\(toLabel) \(account.name)"

            let imported = Transaction(
                amount: amount,
                type: isOutgoing ? .expense : .income,
                date: t.datePosted,
                account: account,
                category: nil,
                note: importedNote,
                payee: counterpart.name
            )
            imported.transferPairId = pairId
            imported.externalId = externalId
            imported.bankDescription = OFXImportMapper.bankDescription(name: t.name, memo: t.memo)
            imported.status = .reconciled

            let other = Transaction(
                amount: amount,
                type: isOutgoing ? .income : .expense,
                date: t.datePosted,
                account: counterpart,
                category: nil,
                note: counterpartNote,
                payee: account.name
            )
            other.transferPairId = pairId
            other.status = .cleared   // adoptée (→ .reconciled) à l'import de l'autre relevé

            context.insert(imported)
            context.insert(other)
            touched.insert(counterpart.persistentModelID)
            added += 1
        }

        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        allAccounts.filter { touched.contains($0.persistentModelID) }
                   .forEach { $0.recalculateBalance() }
        try? context.save()
        return (added, adopted, skipped)
    }

    // MARK: - Vérification du solde bancaire déclaré (LEDGERBAL)

    struct BalanceCheck {
        let delta: Decimal          // solde déclaré − solde app (+ = il manque de l'argent dans l'app)
        let ledgerBalance: Decimal  // solde officiel selon la banque
        let ledgerDate: Date        // date de ce solde (DTASOF, sinon maintenant)
        let currency: String
    }

    /// Compare le solde calculé du compte (post-import) au solde déclaré dans le
    /// relevé. Retourne nil si le relevé n'en déclare pas, si les devises
    /// diffèrent (le mismatch a déjà son propre avertissement), ou si ça balance.
    static func balanceCheck(statement: OFXStatement, account: Account) -> BalanceCheck? {
        guard let ledger = statement.ledgerBalance else { return nil }
        if let cur = statement.currency, cur != account.currency { return nil }
        return balanceCheck(declaredBalance: ledger,
                            declaredDate: statement.ledgerDate ?? .now,
                            account: account)
    }

    /// Version générique : compare un solde déclaré par la source (banque via
    /// LEDGERBAL, agrégateur Flinks…) au solde calculé du compte. Retourne nil
    /// si ça balance. L'appelant garantit la cohérence de devise.
    static func balanceCheck(declaredBalance: Decimal, declaredDate: Date, account: Account) -> BalanceCheck? {
        let delta = declaredBalance - account.balance
        guard delta != 0 else { return nil }
        return BalanceCheck(delta: delta,
                            ledgerBalance: declaredBalance,
                            ledgerDate: declaredDate,
                            currency: account.currency)
    }

    /// Résorbe l'écart. Deux stratégies :
    ///  - le compte n'a AUCUNE transaction manuelle (tout vient d'imports/sync) →
    ///    on cale `initialBalance` (aucun historique utilisateur réécrit) ;
    ///  - sinon → transaction d'ajustement datée du relevé (visible, traçable,
    ///    réversible), statut .reconciled.
    /// `customDelta` remplace le delta calculé si l'utilisateur a saisi son propre montant.
    /// Retourne true si `initialBalance` a été calé, false si une transaction a été créée.
    @discardableResult
    static func applyBalanceAdjustment(_ check: BalanceCheck,
                                       account: Account,
                                       context: ModelContext,
                                       adjustmentLabel: String,
                                       customDelta: Decimal? = nil) -> Bool {
        let delta = customDelta ?? check.delta
        let hasManual = (account.transactions ?? []).contains { $0.externalId == nil }
        if !hasManual {
            account.initialBalance += delta
        } else {
            let tx = Transaction(
                amount: abs(delta),
                type: delta > 0 ? .income : .expense,
                date: check.ledgerDate,
                account: account,
                note: adjustmentLabel,
                payee: adjustmentLabel,
                status: .reconciled
            )
            context.insert(tx)
        }
        account.recalculateBalance()
        try? context.save()
        return !hasManual
    }

    /// Silent anchor: shift `initialBalance` so the computed balance equals the
    /// declared balance, WITHOUT creating any transaction. Used on a bank account's
    /// first sync, or when re-anchoring after a long gap (where the partial history
    /// can't reproduce the balance). Does not save — the caller persists.
    static func anchorBalance(to declaredBalance: Decimal, account: Account) {
        let delta = declaredBalance - account.balance
        guard delta != 0 else { return }
        account.initialBalance += delta
        account.recalculateBalance()
    }
}
