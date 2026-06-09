//
//  RootView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang

    // Widget data sync — triggers WidgetDataWriter when accounts or transactions change
    @Query private var _accounts:     [Account]
    @Query private var _transactions: [Transaction]
    @State private var lockManager = AppLockManager.shared
    @Environment(EntitlementManager.self) private var entitlements

    @State private var selectedTab: Int = 0
    /// FIN-004 — hides financial data in the iOS app switcher screenshot.
    @State private var isObscured: Bool = false
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
        // FIN-004 — Privacy overlay: shown at willResignActive (before iOS takes the
        // app-switcher screenshot), removed when the app becomes active again.
        .overlay {
            if isObscured {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor.opacity(0.6))
                    }
            }
        }
        .task(id: _transactions.count + _accounts.count) {
            // Sync widget data whenever account/transaction count changes
            WidgetDataWriter.write(context: context)
        }
        .onAppear {
            // Sync widget data on first launch
            WidgetDataWriter.write(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            isObscured = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            isObscured = false
        }
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
