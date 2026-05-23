//
//  RootView.swift
//  FinTrack
//

import SwiftUI

struct RootView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var lockManager = AppLockManager.shared

    var body: some View {
        Group {
            if !lockManager.isSetup {
                // First launch: account creation wizard
                SetupAccountView()
                    .environment(lang)
            } else if lockManager.isLocked {
                // App is locked: show lock screen
                LockScreenView()
                    .environment(lang)
                    .transition(.opacity)
            } else {
                // Normal app content
                mainTabs
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lockManager.isLocked)
        .animation(.easeInOut(duration: 0.2), value: lockManager.isSetup)
        // App lifecycle — handle auto-lock
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            lockManager.handleBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            lockManager.handleForeground()
        }
    }

    private var mainTabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label(lang["tab.dashboard"], systemImage: "chart.pie.fill") }

            AccountsView()
                .tabItem { Label(lang["tab.accounts"], systemImage: "building.columns.fill") }

            TransactionsView()
                .tabItem { Label(lang["tab.transactions"], systemImage: "list.bullet.rectangle") }

            BudgetsView()
                .tabItem { Label(lang["tab.budgets"], systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tabItem { Label(lang["tab.settings"], systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
        .withLanguageManager()
}
