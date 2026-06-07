//
//  RootView.swift
//  FinTrack
//

import SwiftUI

struct RootView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var lockManager = AppLockManager.shared
    @Environment(EntitlementManager.self) private var entitlements

    @State private var selectedTab: Int = 0
    /// Deep-link section to open inside SettingsView (loans, creditlines, recurring)
    @State private var settingsDeepLink: String = ""

    var body: some View {
        Group {
            if !lockManager.isSetup {
                SetupAccountView()
                    .environment(lang)
            } else if lockManager.isLocked {
                LockScreenView()
                    .environment(lang)
                    .transition(.opacity)
            } else {
                mainTabs
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lockManager.isLocked)
        .animation(.easeInOut(duration: 0.2), value: lockManager.isSetup)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            lockManager.handleBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            lockManager.handleForeground()
        }
        // Deep link from notification tap
        .onReceive(NotificationCenter.default.publisher(for: .fintrackDeepLink)) { notif in
            guard let tab = notif.userInfo?["tab"] as? Int else { return }
            let section = notif.userInfo?["section"] as? String ?? ""
            withAnimation { selectedTab = tab }
            if tab == 4 { settingsDeepLink = section }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(lang["tab.dashboard"], systemImage: "chart.pie.fill") }
                .tag(0)

            AccountsView()
                .tabItem { Label(lang["tab.accounts"], systemImage: "building.columns.fill") }
                .tag(1)

            TransactionsView()
                .tabItem { Label(lang["tab.transactions"], systemImage: "list.bullet.rectangle") }
                .tag(2)

            BudgetsView()
                .tabItem { Label(lang["tab.budgets"], systemImage: "chart.bar.xaxis") }
                .tag(3)

            SettingsView(deepLink: $settingsDeepLink)
                .tabItem { Label(lang["tab.settings"], systemImage: "gearshape.fill") }
                .tag(4)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
        .withLanguageManager()
}
