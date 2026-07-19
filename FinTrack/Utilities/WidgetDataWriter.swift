//  WidgetDataWriter.swift — Reads SwiftData, writes to App Group UserDefaults, reloads widget timelines

import Foundation
import SwiftData
import WidgetKit
import os

private let widgetLog = Logger(subsystem: "ca.regis.fintrack", category: "widget")

enum WidgetDataWriter {

    static func write(context: ModelContext) {
        widgetLog.info("WidgetDataWriter.write() called")
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

        // True net worth: active accounts (signed) − loans − credit lines, all
        // converted to the primary currency (mirrors NetWorthWidget in the app).
        let fx = ExchangeRateManager.shared
        func toPrimary(_ amount: Decimal, from cur: String) -> Double {
            NSDecimalNumber(decimal: fx.convert(amount, from: cur, to: primaryCurrency)).doubleValue
        }
        let accountsNet = active.reduce(0.0) { $0 + toPrimary($1.balance, from: $1.currency) }
        let loans = (try? context.fetch(FetchDescriptor<Loan>(
            predicate: #Predicate<Loan> { $0.isActive }))) ?? []
        let creditLines = (try? context.fetch(FetchDescriptor<CreditLine>(
            predicate: #Predicate<CreditLine> { $0.isActive }))) ?? []
        let loanDebt = loans.reduce(0.0) { $0 + toPrimary(Decimal($1.calculator.currentBalance), from: $1.currency) }
        let clDebt   = creditLines.reduce(0.0) { $0 + toPrimary($1.currentBalance, from: $1.currency) }
        let netWorth = accountsNet - loanDebt - clDebt

        // Δ net worth since the start of the month. A monthly snapshot lives in the
        // App Group: captured on the first write of each month, then held steady so
        // every later write compares against it. (Very first month: captured at
        // first launch, so the delta runs from install rather than the 1st.)
        let monthKey: String = {
            let c = Calendar.current.dateComponents([.year, .month], from: .now)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        }()
        let groupDefaults = UserDefaults(suiteName: FinTrackWidgetData.appGroupID)
        let snapValueKey = "fintrack.widget.monthStartNetWorth"
        let snapMonthKey = "fintrack.widget.monthStartMonthKey"
        let monthStartNetWorth: Double
        if groupDefaults?.string(forKey: snapMonthKey) == monthKey,
           let saved = groupDefaults?.object(forKey: snapValueKey) as? Double {
            monthStartNetWorth = saved
        } else {
            monthStartNetWorth = netWorth
            groupDefaults?.set(monthKey, forKey: snapMonthKey)
            groupDefaults?.set(netWorth, forKey: snapValueKey)
        }
        let netWorthMonthChange = netWorth - monthStartNetWorth

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

        // Registered-account contribution room per owned type (CELI/CELIAPP/REER).
        // Uses ALL accounts (archived included) because room is historical.
        let plans = (try? context.fetch(FetchDescriptor<RegisteredRoomPlan>())) ?? []
        let roomTypes: [RegisteredType] = [.celi, .celiapp, .reer]
        let registeredRooms: [FinTrackWidgetData.RegisteredRoomEntry] = roomTypes.compactMap { type in
            let hasAccount = accounts.contains { $0.registeredProfile?.registeredType == type }
            guard hasAccount || plans.contains(where: { $0.registeredType == type }) else { return nil }
            guard let plan = plans.first(where: { $0.registeredType == type }),
                  let result = RegisteredRoomService.availableRoom(type: type, plan: plan, accounts: accounts)
            else { return nil }   // owned but no anchor set → nothing to show
            return FinTrackWidgetData.RegisteredRoomEntry(
                type: type.rawValue,
                shortName: type.shortName,
                available: NSDecimalNumber(decimal: result.availableRoom).doubleValue,
                contributed: NSDecimalNumber(decimal: result.lifetimeContributed).doubleValue,
                lifetimeCap: type.lifetimeCap.map { NSDecimalNumber(decimal: $0).doubleValue },
                isOver: result.isOverContributed
            )
        }

        // Active budgets: spent (BudgetCalculator) vs limit, in manual order.
        let budgetModels = (try? context.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate<Budget> { $0.isActive },
            sortBy: [SortDescriptor(\Budget.sortIndex), SortDescriptor(\Budget.createdAt)]))) ?? []
        let budgets: [FinTrackWidgetData.WidgetBudget] = budgetModels.prefix(6).map { b in
            let spent = BudgetCalculator.spent(for: b, in: transactions)
            return FinTrackWidgetData.WidgetBudget(
                id: "\(b.persistentModelID.hashValue)",
                name: b.name,
                spent: NSDecimalNumber(decimal: spent).doubleValue,
                limit: NSDecimalNumber(decimal: b.limitAmount).doubleValue,
                currency: b.currency,
                colorHex: b.colorHex
            )
        }

        // Recent expenses that fall inside a budget (tagged with the budget's colour).
        var budgetTxs: [FinTrackWidgetData.WidgetBudgetTx] = []
        for tx in transactions {   // sorted most-recent first
            guard tx.type == .expense, tx.transferPairId == nil, tx.status.countsTowardBalance else { continue }
            let match = budgetModels.first { b in
                guard tx.account?.currency == b.currency else { return false }
                guard tx.date >= b.period.periodStart() && tx.date < b.period.periodEnd() else { return false }
                if b.categories.isEmpty { return true }
                guard let cat = tx.category else { return false }
                return b.categories.contains { $0.persistentModelID == cat.persistentModelID }
            }
            guard let b = match else { continue }
            budgetTxs.append(FinTrackWidgetData.WidgetBudgetTx(
                id: UUID(),
                label: tx.payee ?? tx.category?.localizedName ?? "Dépense",
                amount: NSDecimalNumber(decimal: tx.amount).doubleValue,
                currency: b.currency,
                colorHex: b.colorHex
            ))
            if budgetTxs.count >= 6 { break }
        }

        // Individual account balances, largest first.
        let widgetAccounts: [FinTrackWidgetData.WidgetAccount] = active
            .sorted { $0.balance > $1.balance }
            .prefix(8)
            .map { a in
                FinTrackWidgetData.WidgetAccount(
                    id: "\(a.persistentModelID.hashValue)",
                    name: a.name,
                    balance: NSDecimalNumber(decimal: a.balance).doubleValue,
                    currency: a.currency,
                    colorHex: a.colorHex,
                    icon: a.iconSystemName
                )
            }

        // Active savings projects: saved so far vs (optional) target.
        let projectModels = (try? context.fetch(FetchDescriptor<SavingsProject>(
            predicate: #Predicate<SavingsProject> { $0.isActive },
            sortBy: [SortDescriptor(\SavingsProject.sortIndex), SortDescriptor(\SavingsProject.createdAt)]))) ?? []
        let savings: [FinTrackWidgetData.WidgetSavings] = projectModels.prefix(6).map { p in
            FinTrackWidgetData.WidgetSavings(
                id: "\(p.persistentModelID.hashValue)",
                name: p.name,
                current: NSDecimalNumber(decimal: p.currentAmount).doubleValue,
                target: p.targetAmount.map { NSDecimalNumber(decimal: $0).doubleValue },
                currency: p.currency,
                colorHex: p.colorHex,
                icon: p.iconSystemName
            )
        }

        let data = FinTrackWidgetData(
            primaryCurrency:    primaryCurrency,
            language:           LanguageManager.shared.current.rawValue,
            balances:           balances,
            netWorth:           netWorth,
            netWorthMonthChange: netWorthMonthChange,
            monthIncome:        monthIncome,
            monthExpense:       monthExpense,
            recentTransactions: Array(recent),
            upcoming:           Array(upcoming),
            registeredRooms:    registeredRooms,
            budgets:            budgets,
            budgetTransactions: budgetTxs,
            accounts:           widgetAccounts,
            accountsTotal:      accountsNet,
            savings:            savings,
            updatedAt:          .now
        )

        let defaults = UserDefaults(suiteName: FinTrackWidgetData.appGroupID)
        if defaults == nil {
            widgetLog.error("App Group UserDefaults nil — group.ca.regis.fintrack not entitled. Add App Groups capability in Xcode.")
        } else {
            widgetLog.info("Writing widget data: \(balances.count) balances, \(recent.count) tx, updatedAt \(Date.now.description)")
        }
        data.save()
        WidgetCenter.shared.reloadAllTimelines()
        widgetLog.info("WidgetCenter.reloadAllTimelines() called")
    }
}
