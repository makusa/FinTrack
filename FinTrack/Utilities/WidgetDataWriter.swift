//  WidgetDataWriter.swift — Reads SwiftData, writes to App Group UserDefaults, reloads widget timelines

import Foundation
import SwiftData
import WidgetKit

enum WidgetDataWriter {

    static func write(context: ModelContext) {
        let accounts     = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        ))) ?? []
        let recurrings   = (try? context.fetch(FetchDescriptor<RecurringTransaction>(
            predicate: #Predicate<RecurringTransaction> { $0.isActive }
        ))) ?? []

        let active = accounts.filter { !$0.isArchived }

        // Primary currency — most common among active accounts
        let primaryCurrency = Dictionary(grouping: active, by: \.currency)
            .max(by: { $0.value.count < $1.value.count })?.key ?? "CAD"

        // Balances by currency, primary first
        let balances: [FinTrackWidgetData.BalanceEntry] = Dictionary(grouping: active, by: \.currency)
            .map { (cur, accs) in
                let total = accs.reduce(Decimal(0)) { $0 + $1.balance }
                return FinTrackWidgetData.BalanceEntry(
                    currency: cur,
                    symbol:   Currencies.info(for: cur).symbol,
                    amount:   NSDecimalNumber(decimal: total).doubleValue
                )
            }
            .sorted { $0.currency == primaryCurrency ? true : ($1.currency == primaryCurrency ? false : $0.currency < $1.currency) }

        // Net worth — naïve sum (no FX conversion)
        let netWorth = balances.first(where: { $0.currency == primaryCurrency })?.amount
            ?? balances.first?.amount ?? 0

        // This-month income / expense (primary currency only)
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let monthTx = transactions.filter { $0.date >= startOfMonth && $0.account?.currency == primaryCurrency }
        let monthIncome  = monthTx.filter { $0.type == .income  }.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
        let monthExpense = monthTx.filter { $0.type == .expense }.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }

        // Recent transactions — last 5
        let recent: [FinTrackWidgetData.WidgetTx] = Array(transactions.prefix(5)).map { tx in
            FinTrackWidgetData.WidgetTx(
                id:       UUID(),
                label:    tx.payee ?? tx.category?.localizedName ?? (tx.type == .income ? "Revenu" : "Dépense"),
                amount:   NSDecimalNumber(decimal: tx.amount).doubleValue,
                currency: tx.account?.currency ?? primaryCurrency,
                isIncome: tx.type == .income
            )
        }

        // Upcoming recurrences — next 30 days
        let today = Calendar.current.startOfDay(for: .now)
        let in30  = Calendar.current.date(byAdding: .day, value: 30, to: today)!
        let upcoming: [FinTrackWidgetData.WidgetEvent] = recurrings
            .filter { $0.nextDueDate >= today && $0.nextDueDate <= in30 }
            .sorted { $0.nextDueDate < $1.nextDueDate }
            .prefix(5)
            .map { r in
                let days = Calendar.current.dateComponents([.day], from: today, to: r.nextDueDate).day ?? 0
                return FinTrackWidgetData.WidgetEvent(
                    id:        UUID(),
                    name:      r.displayTitle,
                    amount:    NSDecimalNumber(decimal: r.amount).doubleValue,
                    currency:  r.account?.currency ?? primaryCurrency,
                    daysUntil: days
                )
            }

        let data = FinTrackWidgetData(
            primaryCurrency:    primaryCurrency,
            balances:           balances,
            netWorth:           netWorth,
            monthIncome:        monthIncome,
            monthExpense:       monthExpense,
            recentTransactions: Array(recent),
            upcoming:           Array(upcoming),
            updatedAt:          .now
        )

        data.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
