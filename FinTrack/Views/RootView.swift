//
//  RootView.swift
//  FinTrack
//

import SwiftUI

struct RootView: View {
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label(lang["tab.dashboard"], systemImage: "chart.pie.fill")
                }

            AccountsView()
                .tabItem {
                    Label(lang["tab.accounts"], systemImage: "building.columns.fill")
                }

            TransactionsView()
                .tabItem {
                    Label(lang["tab.transactions"], systemImage: "list.bullet.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label(lang["tab.settings"], systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
}
