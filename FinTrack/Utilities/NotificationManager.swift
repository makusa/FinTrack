//
//  NotificationManager.swift
//  FinTrack
//
//  Manages local notifications for all upcoming planned expenses:
//  recurring rules, loan payments, credit line minimums, future one-time
//  transactions, and loan prepayments.
//
//  Notification delivery time is always 9:00 AM local time on the reminder day.
//  Identifiers: "fintrack.<type>.<hashValue>[.<dateKey>]"
//

import UserNotifications
import SwiftData
import Foundation

// MARK: - Days-before options

let notificationDaysOptions: [Int] = [1, 2, 3, 5, 7, 14]

// MARK: - Manager

@MainActor
final class NotificationManager: NSObject {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    func requestPermission() async {
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
            center.delegate = self
        } catch {
            print("NotificationManager: permission request failed — \(error)")
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Schedule all

    /// Cancels all pending FinTrack notifications and reschedules from current data.
    func scheduleAll(context: ModelContext) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        // Cancel everything and start fresh
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .filter { $0.identifier.hasPrefix("fintrack.") }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        // Fetch all models
        let recurring   = (try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []
        let loans       = (try? context.fetch(FetchDescriptor<Loan>())) ?? []
        let creditLines = (try? context.fetch(FetchDescriptor<CreditLine>())) ?? []
        let allTx       = (try? context.fetch(FetchDescriptor<Transaction>(sort: [SortDescriptor(\.date)]))) ?? []
        let prepayments = (try? context.fetch(FetchDescriptor<LoanPrepayment>())) ?? []

        // Only future one-time expense transactions
        let futureTx = allTx.filter {
            $0.type == .expense && $0.date > Date() && $0.notificationEnabled
        }

        for rule in recurring where rule.notificationEnabled && rule.isActive && rule.type == .expense {
            await scheduleRecurring(rule)
        }
        for loan in loans where loan.notificationEnabled && loan.isActive {
            await scheduleLoan(loan)
        }
        for cl in creditLines where cl.notificationEnabled && cl.isActive {
            await scheduleCreditLine(cl)
        }
        for tx in futureTx {
            await scheduleTransaction(tx)
        }
        for prep in prepayments where prep.notificationEnabled {
            await schedulePrepayment(prep)
        }
    }

    // MARK: - Recurring transactions

    private func scheduleRecurring(_ rule: RecurringTransaction) async {
        let days = rule.notificationDaysBefore
        let cal  = Calendar.current
        let now  = Date()
        let horizon = cal.date(byAdding: .month, value: 3, to: now) ?? now
        let currency = rule.account?.currency ?? "CAD"
        var date = rule.nextDueDate
        var count = 0

        while date <= horizon, count < 6 {
            if let notifDate = cal.date(byAdding: .day, value: -days, to: date), notifDate > now {
                let content = makeContent(
                    title: "🔔 \(rule.displayTitle)",
                    body: notifBody(
                        amount: rule.amount, currency: currency,
                        dueDate: date, daysBefore: days
                    )
                )
                let id = "fintrack.rec.\(abs(rule.persistentModelID.hashValue)).\(dateKey(date))"
                await scheduleAt(notifDate, id: id, content: content)
                count += 1
            }
            date = rule.frequency.nextDate(after: date)
        }
    }

    // MARK: - Loan payments

    private func scheduleLoan(_ loan: Loan) async {
        let preps   = loan.prepaymentInstances()
        let calc    = loan.calculator
        let elapsed = calc.paymentsElapsedWith(preps)
        guard let entry = calc.scheduleWithPrepayments(preps, from: elapsed + 1, to: elapsed + 1).first
        else { return }

        let days = loan.notificationDaysBefore
        let cal  = Calendar.current
        let now  = Date()
        guard let notifDate = cal.date(byAdding: .day, value: -days, to: entry.date),
              notifDate > now else { return }

        let name = loan.label.isEmpty ? loan.type.label : loan.label
        let content = makeContent(
            title: "🏦 \(name)",
            body: notifBody(
                amount: Decimal(entry.payment), currency: loan.currency,
                dueDate: entry.date, daysBefore: days
            )
        )
        await scheduleAt(notifDate, id: "fintrack.loan.\(abs(loan.persistentModelID.hashValue))", content: content)
    }

    // MARK: - Credit line minimum payments

    private func scheduleCreditLine(_ cl: CreditLine) async {
        guard cl.currentBalance > 0 else { return }
        let days = cl.notificationDaysBefore
        let cal  = Calendar.current
        let now  = Date()

        // Approximate: 1st of next month as minimum payment due date
        var comps  = cal.dateComponents([.year, .month], from: now)
        comps.day  = 1
        var dueDate = cal.date(from: comps) ?? now
        if dueDate <= now {
            dueDate = cal.date(byAdding: .month, value: 1, to: dueDate) ?? now
        }

        guard let notifDate = cal.date(byAdding: .day, value: -days, to: dueDate),
              notifDate > now else { return }

        let content = makeContent(
            title: "💳 \(cl.name)",
            body: notifBody(
                amount: cl.estimatedMinimumPayment, currency: cl.currency,
                dueDate: dueDate, daysBefore: days
            )
        )
        await scheduleAt(notifDate, id: "fintrack.cl.\(abs(cl.persistentModelID.hashValue))", content: content)
    }

    // MARK: - Future one-time transactions

    private func scheduleTransaction(_ tx: Transaction) async {
        let days = tx.notificationDaysBefore
        let cal  = Calendar.current
        let now  = Date()
        guard let notifDate = cal.date(byAdding: .day, value: -days, to: tx.date),
              notifDate > now else { return }

        let name = tx.payee ?? tx.category?.name ?? LanguageManager.shared["tx.type.expense"]
        let currency = tx.account?.currency ?? "CAD"
        let content = makeContent(
            title: "💸 \(name)",
            body: notifBody(
                amount: tx.amount, currency: currency,
                dueDate: tx.date, daysBefore: days
            )
        )
        await scheduleAt(notifDate, id: "fintrack.tx.\(abs(tx.persistentModelID.hashValue))", content: content)
    }

    // MARK: - Loan prepayments

    private func schedulePrepayment(_ prep: LoanPrepayment) async {
        let days     = prep.notificationDaysBefore
        let cal      = Calendar.current
        let now      = Date()
        let horizon  = cal.date(byAdding: .month, value: 3, to: now) ?? now
        let currency = prep.loan?.currency ?? "CAD"
        let loanName = prep.loan?.label ?? ""
        let lang     = LanguageManager.shared

        func content(for date: Date) -> UNMutableNotificationContent {
            makeContent(
                title: "⬆️ \(lang["prepayment.title"])" + (loanName.isEmpty ? "" : " · \(loanName)"),
                body: notifBody(amount: prep.amount, currency: currency, dueDate: date, daysBefore: days)
            )
        }

        if prep.isRecurring, let freq = prep.frequency {
            var date  = prep.startDate
            let end   = prep.endDate ?? horizon
            var count = 0
            while date <= min(end, horizon), count < 4 {
                if let notifDate = cal.date(byAdding: .day, value: -days, to: date), notifDate > now {
                    let id = "fintrack.prep.\(abs(prep.persistentModelID.hashValue)).\(dateKey(date))"
                    await scheduleAt(notifDate, id: id, content: content(for: date))
                    count += 1
                }
                date = freq.nextDate(after: date)
            }
        } else {
            guard let notifDate = cal.date(byAdding: .day, value: -days, to: prep.startDate),
                  notifDate > now else { return }
            let id = "fintrack.prep.\(abs(prep.persistentModelID.hashValue))"
            await scheduleAt(notifDate, id: id, content: content(for: prep.startDate))
        }
    }

    // MARK: - Helpers

    private func scheduleAt(_ date: Date, id: String, content: UNMutableNotificationContent) async {
        var comps   = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour  = 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            print("NotificationManager: failed to add \(id) — \(error)")
        }
    }

    private func makeContent(title: String, body: String) -> UNMutableNotificationContent {
        let c      = UNMutableNotificationContent()
        c.title    = title
        c.body     = body
        c.sound    = .default
        return c
    }

    private func notifBody(amount: Decimal, currency: String, dueDate: Date, daysBefore: Int) -> String {
        let lang    = LanguageManager.shared
        let amtStr  = amount.formatted(asCurrency: currency)
        let dateStr = dueDate.formatted(date: .abbreviated, time: .omitted)
        if daysBefore == 1 {
            return "\(amtStr) · \(lang["notification.tomorrow"]) (\(dateStr))"
        }
        return "\(amtStr) · \(lang.f("notification.inDays", daysBefore)) (\(dateStr))"
    }

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}

// MARK: - Foreground presentation delegate

extension NotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
