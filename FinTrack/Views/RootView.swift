//
//  RootView.swift
//  FinTrack
//

import SwiftUI
import SwiftData
import CoreData

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
    @State private var manageDeepLink: String = ""

    // P2 — iCloud restore prompt
    @AppStorage("fintrack.cloudSyncEnabled") private var cloudSyncEnabled = false
    @AppStorage("fintrack.cloudRestore.handled") private var restoreHandled = false
    @State private var showRestorePrompt = false
    @State private var showReopenNotice = false
    @State private var restoreProbeRan = false
    @State private var dedupeTask: Task<Void, Never>? = nil

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
        .onChange(of: lang.current) {
            // Re-sync so the widget picks up the new in-app language right away.
            WidgetDataWriter.write(context: context)
        }
        .task {
            // Clean duplicate system categories left by the seed/CloudKit race.
            _ = CategoryDeduplicator.dedupeSystemCategories(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            scheduleCategoryDedupe()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            isObscured = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            isObscured = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            lockManager.handleBackground()
            // Refresh widget data on the way out so it reflects the latest state
            // (language, budgets, edits) next time the Home screen is shown.
            WidgetDataWriter.write(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            lockManager.handleForeground()
            scheduleCategoryDedupe()
        }
        // Deep link from notification tap
        .onReceive(NotificationCenter.default.publisher(for: .fintrackDeepLink)) { notif in
            guard let tab = notif.userInfo?["tab"] as? Int else { return }
            let section = notif.userInfo?["section"] as? String ?? ""
            withAnimation { selectedTab = tab }
            if tab == 3 { manageDeepLink = section }
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

            ManageHubView(deepLink: $manageDeepLink)
                .tabItem { Label(lang["tab.manage"], systemImage: "square.grid.2x2.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label(lang["tab.settings"], systemImage: "gearshape.fill") }
                .tag(4)
        }
        .task { await probeForCloudRestore() }
        .onChange(of: entitlements.hasPaidTier) { _, isPaid in
            if isPaid { Task { await probeForCloudRestore() } }
        }
        .alert(lang["cloud.restore.title"], isPresented: $showRestorePrompt) {
            Button(lang["cloud.restore.load"]) {
                cloudSyncEnabled = true
                restoreHandled = true
                showReopenNotice = true
            }
            Button(lang["cloud.restore.fresh"], role: .cancel) {
                restoreHandled = true
            }
        } message: {
            Text(lang["cloud.restore.message"])
        }
        .alert(lang["cloud.restore.reopen.title"], isPresented: $showReopenNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lang["cloud.restore.reopen.message"])
        }
    }

    /// P2 — Offers to load existing iCloud data on a fresh, paid install. Only runs
    /// when paid, sync is off, nothing exists locally, and the user hasn't chosen
    /// yet. "Load" enables sync; data downloads on the next launch (the container
    /// is built CloudKit-backed once, at startup).
    /// Debounced dedupe: collapses a burst of CloudKit remote-change
    /// notifications into a single pass a couple seconds later.
    private func scheduleCategoryDedupe() {
        dedupeTask?.cancel()
        dedupeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            let removed = CategoryDeduplicator.dedupeSystemCategories(context: context)
            if removed > 0 {
                AppLogger.seed.info("CategoryDeduplicator removed \(removed) duplicate(s) after sync")
            }
        }
    }

    private func probeForCloudRestore() async {
        guard entitlements.hasPaidTier,
              !cloudSyncEnabled,
              !restoreHandled,
              !restoreProbeRan,
              _accounts.isEmpty
        else { return }
        restoreProbeRan = true
        if await CloudDataProbe.hasCloudData() {
            showRestorePrompt = true
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
        .withLanguageManager()
}
