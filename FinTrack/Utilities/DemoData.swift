//
//  DemoData.swift
//  FinTrack
//
//  DEBUG-only demonstration dataset used by the screenshot UI-test harness.
//  It is never compiled into Release builds, and only seeded when the app is
//  launched with the -FTDemoMode argument — into an in-memory store, so the
//  developer's real data on disk is never touched.
//

#if DEBUG
import Foundation
import SwiftData

/// Launch-argument switch for the screenshot harness.
enum DemoMode {
    static let launchArgument = "-FTDemoMode"
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum DemoData {

    // MARK: - Helpers

    private static var cal: Calendar { Calendar.current }

    /// Decimal from a string literal — avoids binary floating-point drift.
    private static func d(_ s: String) -> Decimal { Decimal(string: s) ?? 0 }

    /// A date `offset` days from today (negative = past).
    private static func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: .now) ?? .now
    }

    private static func month(_ offset: Int) -> Date {
        cal.date(byAdding: .month, value: offset, to: .now) ?? .now
    }

    // MARK: - Entry point

    /// Populates an empty in-memory store with a realistic Quebec household.
    /// Idempotent guard: does nothing if accounts already exist.
    static func seed(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        guard existing == 0 else { return }

        let cats = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        func cat(_ key: String) -> Category? {
            cats.first { $0.localizationKey == key }
        }

        // ── Comptes ──────────────────────────────────────────────────────
        let cheques = Account(name: "Compte chèques", institution: "Banque Nationale",
                              type: .checking, currency: "CAD",
                              initialBalance: d("2850"), colorHex: "#E4002B")
        let epargne = Account(name: "Épargne d'urgence", institution: "Banque Nationale",
                              type: .savings, currency: "CAD",
                              initialBalance: d("11500"), colorHex: "#34C759")
        let celi = Account(name: "CELI", institution: "Banque Nationale",
                           type: .investment, currency: "CAD",
                           initialBalance: d("28400"), colorHex: "#3478F6")
        let celiapp = Account(name: "CELIAPP", institution: "Banque Nationale",
                              type: .investment, currency: "CAD",
                              initialBalance: d("8000"), colorHex: "#5AC8FA")
        let visa = Account(name: "Visa Infinite", institution: "Banque Nationale",
                           type: .credit, currency: "CAD",
                           initialBalance: 0, colorHex: "#FF9500")
        let usd = Account(name: "Compte USD", institution: "Banque Nationale",
                          type: .checking, currency: "USD",
                          initialBalance: d("1450"), colorHex: "#8E8E93")

        for a in [cheques, epargne, celi, celiapp, visa, usd] { context.insert(a) }

        // ── Profils de comptes enregistrés ───────────────────────────────
        let celiProfile = RegisteredAccountProfile(registeredType: .celi)
        let celiappProfile = RegisteredAccountProfile(registeredType: .celiapp)
        context.insert(celiProfile)
        context.insert(celiappProfile)
        celi.registeredProfile = celiProfile
        celiapp.registeredProfile = celiappProfile

        // Ancres de droits de cotisation (valeurs saisies par l'utilisateur
        // depuis son avis de cotisation de l'ARC — pas des chiffres calculés).
        let year = cal.component(.year, from: .now)
        context.insert(RegisteredRoomPlan(registeredType: .celi,
                                          anchorYear: year,
                                          anchorAmount: d("14500")))
        context.insert(RegisteredRoomPlan(registeredType: .celiapp,
                                          anchorYear: year,
                                          anchorAmount: d("8000"),
                                          lifetimeContributedAtAnchor: d("8000")))

        // ── Transactions ─────────────────────────────────────────────────
        // Ancrées sur le calendrier (jour du mois) plutôt que sur un décalage
        // en jours : autrement « ce mois-ci » paraît vide en début de mois.
        func dateIn(monthsBack: Int, day dom: Int) -> Date? {
            guard let base = cal.date(byAdding: .month, value: -monthsBack, to: .now)
            else { return nil }
            var comps = cal.dateComponents([.year, .month], from: base)
            comps.day  = dom
            comps.hour = 12
            return cal.date(from: comps)
        }

        // (jour du mois, montant, type, bénéficiaire, catégorie, compte)
        let monthlyRows: [(Int, String, TransactionType, String, String, Account)] = [
            (1,  "2412.50", .income,  "Employeur — paie",      "category.salary",        cheques),
            (2,  "1685.00", .expense, "Hypothèque",            "category.housing",       cheques),
            (3,   "142.37", .expense, "IGA",                   "category.grocery",       visa),
            (4,    "92.40", .expense, "Hydro-Québec",          "category.utilities",     cheques),
            (6,    "62.15", .expense, "Restaurant Damas",      "category.restaurant",    visa),
            (8,    "97.00", .expense, "STM — passe mensuelle", "category.transport",     visa),
            (11,  "128.44", .expense, "Metro",                 "category.grocery",       visa),
            (13,   "18.99", .expense, "Netflix",               "category.entertainment", visa),
            (15, "2412.50", .income,  "Employeur — paie",      "category.salary",        cheques),
            (16,   "71.80", .expense, "Essence Petro-Canada",  "category.transport",     visa),
            (18,  "155.12", .expense, "Costco",                "category.grocery",       visa),
            (20,   "88.60", .expense, "Pharmaprix",            "category.health",        visa),
            (22,   "76.90", .expense, "Restaurant Schwartz's", "category.restaurant",    visa),
            (24,   "61.30", .expense, "SAQ",                   "category.grocery",       visa),
            (26,  "112.60", .expense, "Simons",                "category.clothing",      visa),
            (28,  "147.22", .expense, "Metro",                 "category.grocery",       visa),
        ]

        // Virements internes — deux volets liés par transferPairId. Le tableau
        // de bord les exclut des statistiques revenus/dépenses.
        // (jour du mois, montant, libellé, compte source, compte destination)
        let transferRows: [(Int, String, String, Account, Account)] = [
            (5, "1150.00", "Paiement Visa", cheques, visa),
            (15, "500.00", "Virement CELI", cheques, celi),
        ]

        func insertTransfer(amount: Decimal, label: String,
                            from: Account, to: Account, date: Date) {
            let pairId = UUID()
            let debit = Transaction(amount: amount, type: .expense, date: date,
                                    account: from, note: label, payee: label,
                                    status: .reconciled)
            let credit = Transaction(amount: amount, type: .income, date: date,
                                     account: to, note: label, payee: label,
                                     status: .reconciled)
            debit.transferPairId  = pairId
            credit.transferPairId = pairId
            context.insert(debit)
            context.insert(credit)
        }

        for monthsBack in 0...3 {
            for (dom, amount, type, payee, key, account) in monthlyRows {
                guard let date = dateIn(monthsBack: monthsBack, day: dom),
                      date <= .now else { continue }
                context.insert(Transaction(amount: d(amount), type: type, date: date,
                                           account: account, category: cat(key),
                                           payee: payee, status: .reconciled))
            }
            for (dom, amount, label, from, to) in transferRows {
                guard let date = dateIn(monthsBack: monthsBack, day: dom),
                      date <= .now else { continue }
                insertTransfer(amount: d(amount), label: label,
                               from: from, to: to, date: date)
            }
        }

        // Transactions à venir — alimente la section « À venir ».
        let upcoming: [(Int, String, TransactionType, String, String, Account)] = [
            (2,  "1685.00", .expense, "Hypothèque",             "category.housing",       cheques),
            (4,    "97.00", .expense, "STM — passe mensuelle",  "category.transport",     cheques),
            (6,  "2412.50", .income,  "Employeur — paie",       "category.salary",        cheques),
            (11,   "18.99", .expense, "Netflix",                "category.entertainment", visa),
        ]
        for (offset, amount, type, payee, key, account) in upcoming {
            context.insert(Transaction(amount: d(amount), type: type, date: day(offset),
                                       account: account, category: cat(key),
                                       payee: payee, status: .scheduled))
        }

        // ── Budgets ──────────────────────────────────────────────────────
        let budgets: [(String, String, String, String, [String])] = [
            ("Alimentation", "650",  "#34C759", "cart.fill",  ["category.grocery"]),
            ("Restaurants",  "250",  "#FF9500", "fork.knife", ["category.restaurant"]),
            ("Transport",    "200",  "#3478F6", "car.fill",   ["category.transport"]),
            ("Loisirs",      "150",  "#AF52DE", "film.fill",  ["category.entertainment"]),
        ]
        for (idx, b) in budgets.enumerated() {
            let budget = Budget(name: b.0, limitAmount: d(b.1), currency: "CAD",
                                period: .monthly, colorHex: b.2, iconSystemName: b.3,
                                categories: b.4.compactMap { cat($0) })
            budget.sortIndex = idx
            context.insert(budget)
        }

        // ── Hypothèque ───────────────────────────────────────────────────
        let hypo = Loan(label: "Hypothèque — Rosemont",
                        lenderName: "Banque Nationale",
                        type: .mortgage,
                        currency: "CAD",
                        originalPrincipal: d("385000"),
                        annualInterestRate: d("4.79"),   // pourcentage, pas fraction
                        termMonths: 300,
                        frequency: .biweeklyAccelerated,
                        compounding: .semiAnnual,        // loi canadienne sur l'intérêt
                        firstPaymentDate: month(-26),
                        account: cheques)
        context.insert(hypo)

        let auto = Loan(label: "Prêt auto — RAV4",
                        lenderName: "Banque Nationale",
                        type: .auto,
                        currency: "CAD",
                        originalPrincipal: d("32000"),
                        annualInterestRate: d("6.95"),
                        termMonths: 72,
                        frequency: .monthly,
                        compounding: .monthly,
                        firstPaymentDate: month(-14),
                        account: cheques)
        context.insert(auto)

        // ── Marge de crédit ──────────────────────────────────────────────
        let marge = CreditLine(name: "Marge de crédit personnelle",
                               lenderName: "Banque Nationale",
                               currency: "CAD",
                               creditLimit: d("25000"),
                               annualInterestRate: d("8.45"),
                               compounding: .daily,
                               minimumPaymentType: .interestOnly,
                               account: cheques)
        marge.statementDay = 15
        context.insert(marge)

        let entries: [(CreditLineEntryType, String, Int, String)] = [
            (.draw,      "6000.00", -75, "Rénovation cuisine"),
            (.repayment,  "800.00", -45, "Remboursement"),
            (.repayment,  "800.00", -15, "Remboursement"),
        ]
        for (type, amount, offset, note) in entries {
            let e = CreditLineEntry(type: type, amount: d(amount),
                                    date: day(offset), note: note)
            e.creditLine = marge
            context.insert(e)
        }

        // ── Projets d'épargne ────────────────────────────────────────────
        let voyage = SavingsProject(name: "Voyage au Japon",
                                    iconSystemName: "airplane",
                                    colorHex: "#FF2D92",
                                    currency: "CAD",
                                    currentAmount: d("2400"),
                                    targetAmount: d("6000"),
                                    monthlyContribution: d("300"),
                                    targetDate: month(12),
                                    account: epargne)
        context.insert(voyage)

        let urgence = SavingsProject(name: "Fonds d'urgence",
                                     iconSystemName: "shield.fill",
                                     colorHex: "#34C759",
                                     currency: "CAD",
                                     currentAmount: d("11500"),
                                     targetAmount: d("18000"),
                                     monthlyContribution: d("400"),
                                     targetDate: month(18),
                                     account: epargne)
        context.insert(urgence)

        // ── Persistance + recalcul des soldes ────────────────────────────
        do {
            try context.save()
        } catch {
            AppLogger.seed.error("DemoData seed failed: \(error, privacy: .public)")
            return
        }

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        accounts.forEach { $0.recalculateBalance() }
        try? context.save()
    }
}
#endif
