//
//  DashboardConfigManager.swift
//  FinTrack
//
//  @Observable singleton managing the user's dashboard layout.
//  Configuration is persisted in UserDefaults as JSON.
//
//  Widget identity is stable (raw String) so future additions
//  don't break existing saved layouts.
//

import SwiftUI

// MARK: - Widget identifiers

enum DashboardWidgetID: String, CaseIterable, Codable, Identifiable {
    // Always visible (pinned, cannot be removed)
    case globalBalance      = "globalBalance"

    // Removable / reorderable
    case accountsCarousel   = "accountsCarousel"
    case monthSummary       = "monthSummary"
    case loans              = "loans"
    case creditLines        = "creditLines"
    case cashFlow           = "cashFlow"
    case budgets            = "budgets"
    case savingsGoals       = "savingsGoals"
    case balanceProjection  = "balanceProjection"
    case incomeVsExpenses   = "incomeVsExpenses"
    case categoryBreakdown  = "categoryBreakdown"
    case upcomingRecurring  = "upcomingRecurring"
    case recentTransactions = "recentTransactions"

    var id: String { rawValue }

    var isPinned: Bool { self == .globalBalance }

    var title: String {
        let lang = LanguageManager.shared
        switch self {
        case .globalBalance:      return lang["dashboard.globalBalance"]
        case .accountsCarousel:   return lang["dashboard.myAccounts"]
        case .monthSummary:       return lang["dashboard.thisMonth"]
        case .loans:              return lang["loan.title"]
        case .creditLines:        return lang["cl.title"]
        case .cashFlow:           return lang["cashflow.title"]
        case .budgets:            return lang["budget.title"]
        case .savingsGoals:       return lang["savings.title"]
        case .balanceProjection:  return lang["analytics.balanceProjection"]
        case .incomeVsExpenses:   return lang["analytics.incomeExpense"]
        case .categoryBreakdown:  return lang["analytics.categoryBreakdown"]
        case .upcomingRecurring:  return lang["dashboard.upcoming"]
        case .recentTransactions: return lang["dashboard.recentTx"]
        }
    }

    var icon: String {
        switch self {
        case .globalBalance:      return "globe"
        case .accountsCarousel:   return "building.columns.fill"
        case .monthSummary:       return "calendar"
        case .loans:              return "banknote.fill"
        case .creditLines:        return "creditcard.fill"
        case .cashFlow:           return "arrow.left.arrow.right.circle.fill"
        case .budgets:            return "chart.bar.doc.horizontal"
        case .savingsGoals:       return "star.fill"
        case .balanceProjection:  return "chart.line.uptrend.xyaxis"
        case .incomeVsExpenses:   return "chart.bar.fill"
        case .categoryBreakdown:  return "chart.pie.fill"
        case .upcomingRecurring:  return "clock.fill"
        case .recentTransactions: return "list.bullet.rectangle"
        }
    }

    var description: String {
        let lang = LanguageManager.shared
        switch self {
        case .globalBalance:      return lang["widget.desc.globalBalance"]
        case .accountsCarousel:   return lang["widget.desc.accounts"]
        case .monthSummary:       return lang["widget.desc.monthSummary"]
        case .loans:              return lang["widget.desc.loans"]
        case .creditLines:        return lang["widget.desc.creditLines"]
        case .cashFlow:           return lang["widget.desc.cashFlow"]
        case .budgets:            return lang["widget.desc.budgets"]
        case .savingsGoals:       return lang["widget.desc.savings"]
        case .balanceProjection:  return lang["widget.desc.balanceProjection"]
        case .incomeVsExpenses:   return lang["widget.desc.incomeVsExpenses"]
        case .categoryBreakdown:  return lang["widget.desc.categoryBreakdown"]
        case .upcomingRecurring:  return lang["widget.desc.upcoming"]
        case .recentTransactions: return lang["widget.desc.recent"]
        }
    }
}

// MARK: - Persistent config model

private struct DashboardConfigData: Codable {
    var enabledOrder: [String]   // rawValues of enabled widgets in display order
    var disabledSet:  [String]   // rawValues of widgets in the library but not shown
}

// MARK: - Manager

@Observable
final class DashboardConfigManager {

    static let shared = DashboardConfigManager()

    private let udKey = "dashboardConfig_v1"

    // MARK: State

    /// Widgets shown on the dashboard, in display order (pinned first).
    private(set) var enabled: [DashboardWidgetID] = []

    /// Widgets in the library but not displayed.
    private(set) var disabled: [DashboardWidgetID] = []

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Public API

    func move(from source: IndexSet, to destination: Int) {
        // Don't allow moving pinned widgets or moving above them
        var mutable = enabled
        mutable.move(fromOffsets: source, toOffset: destination)
        // Ensure pinned widget stays first
        if let pinnedIdx = mutable.firstIndex(where: { $0.isPinned }),
           pinnedIdx != 0 {
            let pinned = mutable.remove(at: pinnedIdx)
            mutable.insert(pinned, at: 0)
        }
        enabled = mutable
        save()
    }

    func disable(_ widget: DashboardWidgetID) {
        guard !widget.isPinned else { return }
        enabled.removeAll { $0 == widget }
        if !disabled.contains(widget) { disabled.append(widget) }
        save()
    }

    func enable(_ widget: DashboardWidgetID) {
        disabled.removeAll { $0 == widget }
        if !enabled.contains(widget) { enabled.append(widget) }
        save()
    }

    func resetToDefaults() {
        enabled  = DashboardWidgetID.allCases
        disabled = []
        save()
    }

    // MARK: - Persistence

    private func save() {
        let data = DashboardConfigData(
            enabledOrder: enabled.map  { $0.rawValue },
            disabledSet:  disabled.map { $0.rawValue }
        )
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: udKey)
        }
    }

    private func load() {
        guard let raw  = UserDefaults.standard.data(forKey: udKey),
              let data = try? JSONDecoder().decode(DashboardConfigData.self, from: raw)
        else {
            resetToDefaults()
            return
        }

        let all = Set(DashboardWidgetID.allCases.map { $0.rawValue })
        // Restore enabled order, filtering unknown IDs
        let restoredEnabled = data.enabledOrder
            .compactMap { DashboardWidgetID(rawValue: $0) }
            .filter { all.contains($0.rawValue) }

        // Any new widget added since the user last configured appears in disabled
        let known = Set(restoredEnabled.map { $0.rawValue } + data.disabledSet)
        let newWidgets = DashboardWidgetID.allCases.filter { !known.contains($0.rawValue) }

        let restoredDisabled = data.disabledSet
            .compactMap { DashboardWidgetID(rawValue: $0) }

        enabled  = restoredEnabled + newWidgets.filter { !$0.isPinned }
        disabled = restoredDisabled

        // Always ensure pinned widget is present and first
        if !enabled.contains(.globalBalance) { enabled.insert(.globalBalance, at: 0) }
        if enabled.first != .globalBalance,
           let idx = enabled.firstIndex(of: .globalBalance) {
            enabled.remove(at: idx)
            enabled.insert(.globalBalance, at: 0)
        }
    }
}
