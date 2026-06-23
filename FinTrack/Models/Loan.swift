//
//  Loan.swift
//  FinTrack
//
//  Loan model + pure-math amortization calculator.
//
//  Amortization math uses Double internally (acceptable precision for display);
//  stored amounts (originalPrincipal, annualInterestRate) remain Decimal.
//
//  Canadian mortgage compounding: semi-annual by law (Interest Act).
//  Personal/auto loans: typically monthly compounding.
//

import Foundation
import SwiftData

// MARK: - Enums

enum LoanType: String, CaseIterable, Identifiable {
    case mortgage    // Hypothèque
    case auto        // Prêt automobile
    case personal    // Prêt personnel
    case student     // Prêt étudiant
    case other       // Autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mortgage: return LanguageManager.shared["loan.type.mortgage"]
        case .auto:     return LanguageManager.shared["loan.type.auto"]
        case .personal: return LanguageManager.shared["loan.type.personal"]
        case .student:  return LanguageManager.shared["loan.type.student"]
        case .other:    return LanguageManager.shared["loan.type.other"]
        }
    }

    var iconSystemName: String {
        switch self {
        case .mortgage: return "house.fill"
        case .auto:     return "car.fill"
        case .personal: return "person.fill"
        case .student:  return "book.fill"
        case .other:    return "doc.fill"
        }
    }

    // MARK: - Smart defaults per loan type

    struct Defaults {
        let termYears:       Int
        let termExtraMonths: Int
        let frequency:       LoanPaymentFrequency
        let compounding:     LoanCompounding
    }

    /// Returns market-appropriate default parameters for this loan type in Canada.
    var defaults: Defaults {
        switch self {
        case .mortgage:
            // 25-year amortization; semi-annual compounding required by Canadian law;
            // biweekly accelerated saves ~3 years vs monthly.
            return Defaults(termYears: 25, termExtraMonths: 0,
                            frequency: .biweeklyAccelerated, compounding: .semiAnnual)
        case .auto:
            // 60-month (5-year) term is the Canadian market standard for auto loans.
            return Defaults(termYears: 5, termExtraMonths: 0,
                            frequency: .monthly, compounding: .monthly)
        case .personal:
            // Personal loans: 1–5 years; 3 years is the median.
            return Defaults(termYears: 3, termExtraMonths: 0,
                            frequency: .monthly, compounding: .monthly)
        case .student:
            // NSLSC repayment assistance: up to 10 years for federal student loans.
            return Defaults(termYears: 10, termExtraMonths: 0,
                            frequency: .monthly, compounding: .monthly)
        case .other:
            return Defaults(termYears: 5, termExtraMonths: 0,
                            frequency: .monthly, compounding: .monthly)
        }
    }

    /// Convenience — kept for backward compatibility.
    var defaultCompounding: LoanCompounding { defaults.compounding }
}

enum LoanPaymentFrequency: String, CaseIterable, Identifiable {
    case monthly             // Mensuel        — 12 versements/an
    case biweeklyAccelerated // Bihebdo accéléré — 26 versements/an = 13 mensualités → rembourse plus vite
    case biweekly            // Bihebdomadaire — 26 versements/an
    case weekly              // Hebdomadaire   — 52 versements/an

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly:             return LanguageManager.shared["loan.freq.monthly"]
        case .biweeklyAccelerated: return LanguageManager.shared["loan.freq.biweeklyAcc"]
        case .biweekly:            return LanguageManager.shared["loan.freq.biweekly"]
        case .weekly:              return LanguageManager.shared["loan.freq.weekly"]
        }
    }

    var paymentsPerYear: Int {
        switch self {
        case .monthly:             return 12
        case .biweeklyAccelerated: return 26
        case .biweekly:            return 26
        case .weekly:              return 52
        }
    }

    var recurringFrequency: RecurrenceFrequency {
        switch self {
        case .monthly:             return .monthly
        case .biweeklyAccelerated: return .biweekly
        case .biweekly:            return .biweekly
        case .weekly:              return .weekly
        }
    }
}

enum LoanCompounding: String, CaseIterable, Identifiable {
    case monthly    // Mensuelle  (prêts perso, auto, étudiant)
    case semiAnnual // Semestrielle (hypothèques canadiennes — loi sur les intérêts)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly:    return LanguageManager.shared["loan.compound.monthly"]
        case .semiAnnual: return LanguageManager.shared["loan.compound.semiAnnual"]
        }
    }
}

// MARK: - Amortization entry

struct AmortizationEntry: Identifiable {
    let id = UUID()
    let paymentNumber: Int
    let date: Date
    let payment: Double
    let interest: Double
    let principal: Double
    let balance: Double
}

// MARK: - Calculator (stateless, pure Double math)

struct LoanCalculator {
    let principal: Double
    let annualRatePercent: Double   // e.g. 5.5
    let termMonths: Int
    let frequency: LoanPaymentFrequency
    let compounding: LoanCompounding
    let firstPaymentDate: Date
    /// Optional manual override of the periodic payment. When set, the amortization
    /// (schedule, payoff, interest) is computed from THIS payment instead of the formula.
    var customPayment: Double? = nil

    // MARK: Periodic rate

    /// Effective interest rate per payment period.
    var periodicRate: Double {
        let annual = annualRatePercent / 100.0
        switch compounding {
        case .monthly:
            // Simple: divide annual rate by periods per year
            return annual / Double(frequency.paymentsPerYear)
        case .semiAnnual:
            // Canadian law: nominal rate compounded semi-annually
            // Effective semi-annual rate:
            let r_semi = annual / 2.0
            // Convert to effective monthly rate:
            let r_monthly = pow(1.0 + r_semi, 1.0 / 6.0) - 1.0
            // Convert to effective rate per payment period:
            if frequency.paymentsPerYear == 12 { return r_monthly }
            return pow(1.0 + r_monthly, 12.0 / Double(frequency.paymentsPerYear)) - 1.0
        }
    }

    // MARK: Total number of payments

    /// Regular payment periods over the full term.
    var totalPayments: Int {
        termMonths * frequency.paymentsPerYear / 12
    }

    // MARK: Payment amount

    /// For biweekly accelerated: payment = monthly_payment / 2.
    /// For all others: standard amortization formula.
    var paymentAmount: Double {
        if let cp = customPayment { return cp }
        let r = periodicRate
        let n = Double(totalPayments)
        let p = principal

        if frequency == .biweeklyAccelerated {
            // Monthly payment for same loan (12 payments/year, same rate)
            let r_monthly: Double
            switch compounding {
            case .monthly:    r_monthly = annualRatePercent / 100.0 / 12.0
            case .semiAnnual:
                let r_semi = annualRatePercent / 100.0 / 2.0
                r_monthly = pow(1.0 + r_semi, 1.0 / 6.0) - 1.0
            }
            let n_monthly = Double(termMonths)
            if r_monthly == 0 { return p / n_monthly / 2.0 }
            let monthly = p * r_monthly * pow(1 + r_monthly, n_monthly)
                        / (pow(1 + r_monthly, n_monthly) - 1)
            return monthly / 2.0
        }

        if r == 0 { return p / n }
        return p * r * pow(1 + r, n) / (pow(1 + r, n) - 1)
    }

    // MARK: Effective number of payments (biweekly accelerated pays off early)

    /// Actual number of payments needed (may be less than totalPayments for accelerated).
    var effectivePayments: Int {
        // Manual payment: solve for the real number of periods to reach a zero balance.
        if customPayment != nil {
            let r = periodicRate
            let m = paymentAmount
            let p = principal
            let cap = totalPayments * 5
            if m <= 0 { return totalPayments }
            if r == 0 { return min(Int(ceil(p / m)), cap) }
            let arg = 1.0 - p * r / m
            if arg <= 0 { return cap }                 // payment <= interest: never clears
            return min(Int(ceil(-log(arg) / log(1.0 + r))), cap)
        }
        if frequency != .biweeklyAccelerated { return totalPayments }
        let r = periodicRate
        let m = paymentAmount
        let p = principal
        if r == 0 || m == 0 { return totalPayments }
        // Solve: n = -ln(1 - p*r/m) / ln(1+r)
        let arg = 1.0 - p * r / m
        if arg <= 0 { return totalPayments }
        return Int(ceil(-log(arg) / log(1.0 + r)))
    }

    // MARK: Payoff date

    var payoffDate: Date {
        let cal = Calendar.current
        let periodsPerYear = frequency.paymentsPerYear
        // Each period is approximately (365.25 / periodsPerYear) days
        let daysPerPeriod = 365.25 / Double(periodsPerYear)
        let totalDays = daysPerPeriod * Double(effectivePayments)
        return cal.date(byAdding: .day, value: Int(totalDays), to: firstPaymentDate) ?? firstPaymentDate
    }

    // MARK: Summary totals

    var totalAmountPaid: Double { paymentAmount * Double(effectivePayments) }
    var totalInterest: Double   { totalAmountPaid - principal }

    // MARK: Balance after k payments

    func balance(after k: Int) -> Double {
        let r = periodicRate
        let m = paymentAmount
        let p = principal
        if k <= 0 { return p }
        if r == 0 { return max(0, p - m * Double(k)) }
        let balance = p * pow(1 + r, Double(k)) - m * (pow(1 + r, Double(k)) - 1) / r
        return max(0, balance)
    }

    // MARK: Payments elapsed today

    var paymentsElapsedToday: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let first = cal.startOfDay(for: firstPaymentDate)
        guard today >= first else { return 0 }
        let periodsPerYear = frequency.paymentsPerYear
        let daysPerPeriod = 365.25 / Double(periodsPerYear)
        let daysDiff = cal.dateComponents([.day], from: first, to: today).day ?? 0
        return min(Int(Double(daysDiff) / daysPerPeriod), effectivePayments)
    }

    var currentBalance: Double { balance(after: paymentsElapsedToday) }
    var principalPaid: Double  { principal - currentBalance }
    var interestPaidToDate: Double {
        let paid = paymentAmount * Double(paymentsElapsedToday)
        return max(0, paid - principalPaid)
    }
    var paymentsRemaining: Int { max(0, effectivePayments - paymentsElapsedToday) }

    var progressFraction: Double {
        guard principal > 0 else { return 0 }
        return min(1, principalPaid / principal)
    }

    // MARK: Date of payment k (1-indexed)

    func paymentDate(_ k: Int) -> Date {
        let cal = Calendar.current
        let daysPerPeriod = 365.25 / Double(frequency.paymentsPerYear)
        let days = Int(round(Double(k - 1) * daysPerPeriod))
        return cal.date(byAdding: .day, value: days, to: firstPaymentDate) ?? firstPaymentDate
    }

    // MARK: Full amortization schedule

    /// Generate the full schedule from payment `from` to payment `to` (1-indexed, inclusive).
    func schedule(from: Int = 1, to: Int? = nil) -> [AmortizationEntry] {
        let end = to ?? effectivePayments
        var entries: [AmortizationEntry] = []
        var bal = balance(after: from - 1)
        let r = periodicRate
        let m = paymentAmount

        for k in from...max(from, end) {
            let interest = bal * r
            let principal = min(m - interest, bal)
            let payment = interest + principal
            bal = max(0, bal - principal)
            entries.append(AmortizationEntry(
                paymentNumber: k,
                date: paymentDate(k),
                payment: payment,
                interest: interest,
                principal: principal,
                balance: bal
            ))
            if bal <= 0 { break }
        }
        return entries
    }
}


// MARK: - LoanCalculator — Prepayment-aware methods

extension LoanCalculator {

    // MARK: Full step-by-step simulation

    /// Generates a complete amortization schedule incorporating the given prepayments.
    /// Prepayments that fall on or before a payment date reduce the principal *before*
    /// that period's interest is computed, which models the standard Canadian convention
    /// (open prepayment privilege applied at each payment anniversary or anytime for
    /// variable-rate mortgages).
    ///
    /// Returns entries only for payment numbers in [startK, endK].
    func scheduleWithPrepayments(
        _ prepayments: [PrepaymentInfo],
        from startK: Int = 1,
        to endK: Int? = nil
    ) -> [AmortizationEntry] {
        guard !prepayments.isEmpty else {
            return schedule(from: startK, to: endK)
        }

        var bal = principal
        let r = periodicRate
        let m = paymentAmount
        var all: [AmortizationEntry] = []
        let sorted = prepayments.filter { $0.amount > 0 }.sorted { $0.date < $1.date }
        var pIdx = 0

        // Absorb prepayments that arrive before the very first payment date
        while pIdx < sorted.count && sorted[pIdx].date < firstPaymentDate {
            bal = max(0, bal - sorted[pIdx].amount)
            pIdx += 1
        }

        let maxK = totalPayments + 500   // upper safety limit
        for k in 1 ... maxK {
            guard bal > 0.005 else { break }

            let payDate = paymentDate(k)

            // Absorb prepayments on or before this payment date
            while pIdx < sorted.count && sorted[pIdx].date <= payDate {
                bal = max(0, bal - sorted[pIdx].amount)
                pIdx += 1
            }
            guard bal > 0.005 else { break }

            let interest      = bal * r
            let principalPart = min(m - interest, bal)
            let payment       = interest + principalPart
            bal = max(0, bal - principalPart)

            all.append(AmortizationEntry(
                paymentNumber: k,
                date: payDate,
                payment: payment,
                interest: interest,
                principal: principalPart,
                balance: bal
            ))
            if bal <= 0.005 { break }
        }

        let filtered = all.filter { $0.paymentNumber >= startK }
        if let end = endK { return filtered.filter { $0.paymentNumber <= end } }
        return filtered
    }

    // MARK: Derived metrics

    /// Current outstanding balance accounting for all prepayments made so far.
    func currentBalanceWith(_ prepayments: [PrepaymentInfo]) -> Double {
        guard !prepayments.isEmpty else { return currentBalance }
        let today = Calendar.current.startOfDay(for: .now)
        // Full simulation from beginning
        let all = scheduleWithPrepayments(prepayments)
        let elapsed = all.filter { Calendar.current.startOfDay(for: $0.date) <= today }
        if elapsed.isEmpty {
            // No regular payment yet — subtract any early prepayments
            let past = prepayments.filter { $0.date <= today }
            return max(0, past.reduce(principal) { $0 - $1.amount })
        }
        return elapsed.last?.balance ?? currentBalance
    }

    /// Number of regular payments that have been made as of today, with prepayments.
    func paymentsElapsedWith(_ prepayments: [PrepaymentInfo]) -> Int {
        guard !prepayments.isEmpty else { return paymentsElapsedToday }
        let today = Calendar.current.startOfDay(for: .now)
        let all = scheduleWithPrepayments(prepayments)
        return all.filter { Calendar.current.startOfDay(for: $0.date) <= today }.count
    }

    /// Number of regular payments still remaining, with prepayments.
    func paymentsRemainingWith(_ prepayments: [PrepaymentInfo]) -> Int {
        guard !prepayments.isEmpty else { return paymentsRemaining }
        let today = Calendar.current.startOfDay(for: .now)
        let all = scheduleWithPrepayments(prepayments)
        return all.filter { Calendar.current.startOfDay(for: $0.date) > today }.count
    }

    /// Estimated payoff date with prepayments.
    func payoffDateWith(_ prepayments: [PrepaymentInfo]) -> Date {
        guard !prepayments.isEmpty else { return payoffDate }
        let all = scheduleWithPrepayments(prepayments)
        return all.last?.date ?? payoffDate
    }

    /// Total interest that will be paid over the life of the loan, with prepayments.
    func totalInterestWith(_ prepayments: [PrepaymentInfo]) -> Double {
        guard !prepayments.isEmpty else { return totalInterest }
        let all = scheduleWithPrepayments(prepayments)
        return all.reduce(0) { $0 + $1.interest }
    }

    /// Total amount paid (regular payments only, excluding lump-sum prepayments).
    func totalAmountPaidWith(_ prepayments: [PrepaymentInfo]) -> Double {
        guard !prepayments.isEmpty else { return totalAmountPaid }
        let all = scheduleWithPrepayments(prepayments)
        return all.reduce(0) { $0 + $1.payment }
    }

    // MARK: Savings vs baseline (without any prepayments)

    struct PrepaymentSavings {
        let paymentsSaved: Int          // fewer regular payments
        let interestSaved: Double       // interest dollars saved
        let timeShortened: DateComponents  // calendar delta
        let newPayoffDate: Date
    }

    func savingsVsBaseline(_ prepayments: [PrepaymentInfo]) -> PrepaymentSavings {
        let basePayoffDate = payoffDate
        let newPayoff = payoffDateWith(prepayments)
        let baseInterest = totalInterest
        let newInterest = totalInterestWith(prepayments)

        let baseCount = effectivePayments
        let newCount = scheduleWithPrepayments(prepayments).count
        let saved = max(0, baseCount - newCount)
        let interestSaved = max(0, baseInterest - newInterest)

        let delta = Calendar.current.dateComponents(
            [.year, .month],
            from: newPayoff,
            to: basePayoffDate
        )

        return PrepaymentSavings(
            paymentsSaved: saved,
            interestSaved: interestSaved,
            timeShortened: delta,
            newPayoffDate: newPayoff
        )
    }

    /// Progress fraction (principal paid / total) with prepayments.
    func progressFractionWith(_ prepayments: [PrepaymentInfo]) -> Double {
        guard principal > 0 else { return 0 }
        let remaining = currentBalanceWith(prepayments)
        return min(1, max(0, (principal - remaining) / principal))
    }
}

// MARK: - Model

@Model
final class Loan {
    var label: String = ""
    var lenderName: String = ""
    var typeRaw: String = LoanType.mortgage.rawValue
    var currency: String = "CAD"
    var originalPrincipal: Decimal = 0
    var annualInterestRate: Decimal = 0    // percent, e.g. 5.5 (NOT 0.055)
    var termMonths: Int = 0
    var customPaymentAmount: Decimal? = nil   // manual override of the periodic payment
    var frequencyRaw: String = LoanPaymentFrequency.monthly.rawValue
    var compoundingRaw: String = LoanCompounding.semiAnnual.rawValue
    var firstPaymentDate: Date = Date.now
    var isActive: Bool = true
    // MARK: Notification settings
    var notificationEnabled: Bool = false
    var notificationDaysBefore: Int = 3


    var notes: String?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Account.loans)
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \LoanPrepayment.loan)
    var prepayments: [LoanPrepayment]? = []

    /// Recurring rule generating this loan's payments (deleted with the loan).
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransaction.loan)
    var paymentRule: RecurringTransaction?

    // MARK: Accessors

    var type: LoanType {
        get { LoanType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var frequency: LoanPaymentFrequency {
        get { LoanPaymentFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var compounding: LoanCompounding {
        get { LoanCompounding(rawValue: compoundingRaw) ?? .monthly }
        set { compoundingRaw = newValue.rawValue }
    }

    // MARK: Calculator

    var calculator: LoanCalculator {
        LoanCalculator(
            principal: (originalPrincipal as NSDecimalNumber).doubleValue,
            annualRatePercent: (annualInterestRate as NSDecimalNumber).doubleValue,
            termMonths: termMonths,
            frequency: frequency,
            compounding: compounding,
            firstPaymentDate: firstPaymentDate,
            customPayment: customPaymentAmount.map { ($0 as NSDecimalNumber).doubleValue }
        )
    }


    // MARK: Prepayment helpers

    /// Expands all LoanPrepayment rules into concrete (date, amount) pairs up to `horizon`.
    /// If `horizon` is nil, uses the original loan payoff date + 10 years as a safety cap.
    func prepaymentInstances(upTo horizon: Date? = nil) -> [PrepaymentInfo] {
        let cal = Calendar.current
        let cap = horizon ?? cal.date(byAdding: .year, value: 10, to: calculator.payoffDate) ?? calculator.payoffDate
        var result: [PrepaymentInfo] = []

        for prep in (prepayments ?? []) {
            let amt = (prep.amount as NSDecimalNumber).doubleValue
            guard amt > 0 else { continue }

            if prep.isRecurring, let freq = prep.frequency {
                var cur = prep.startDate
                let end = prep.endDate ?? cap
                while cur <= min(end, cap) {
                    result.append(PrepaymentInfo(amount: amt, date: cur))
                    cur = freq.nextDate(after: cur)
                }
            } else {
                result.append(PrepaymentInfo(amount: amt, date: prep.startDate))
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    /// True if this loan has at least one active prepayment defined.
    var hasPrepayments: Bool { !(prepayments ?? []).isEmpty }

    // MARK: Init

    init(
        label: String,
        lenderName: String,
        type: LoanType,
        currency: String,
        originalPrincipal: Decimal,
        annualInterestRate: Decimal,
        termMonths: Int,
        frequency: LoanPaymentFrequency,
        compounding: LoanCompounding,
        firstPaymentDate: Date,
        account: Account? = nil,
        notes: String? = nil
    ) {
        self.label = label
        self.lenderName = lenderName
        self.typeRaw = type.rawValue
        self.currency = currency
        self.originalPrincipal = originalPrincipal
        self.annualInterestRate = annualInterestRate
        self.termMonths = termMonths
        self.frequencyRaw = frequency.rawValue
        self.compoundingRaw = compounding.rawValue
        self.firstPaymentDate = firstPaymentDate
        self.isActive = true
        self.account = account
        self.notes = notes
        self.createdAt = .now
    }
}
