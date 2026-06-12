//
//  SettingsView.swift
//  FinTrack
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var deepLink: String

    @Environment(\.modelContext) private var context

    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rateManager
    @Environment(EntitlementManager.self) private var entitlements

    @AppStorage("fintrack.cloudSyncEnabled") private var cloudSyncEnabled = false
    @State private var showCloudRestartAlert = false
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    @State private var showExporter = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var confirmReset = false
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            Form {
                languageSection
                exchangeRatesSection
                subscriptionSection
                bankSyncSection
                securitySection
                notificationsSection
                cloudSyncSection
                dataSection
                statsSection
                dangerZoneSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle(lang["settings.title"])
            .navigationDestination(for: String.self) { section in
                switch section {
                case "loans":       LoansView()
                case "creditlines": CreditLinesView()
                case "recurring":   RecurrencesView()
                default:            EmptyView()
                }
            }
            .onChange(of: deepLink) { _, section in
                guard !section.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    handleDeepLink(section)
                    deepLink = ""
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: defaultExportFilename
            ) { result in
                switch result {
                case .success(_):
                    AppLogger.export.info("CSV exported successfully")
                case .failure(let error):
                    AppLogger.export.error("CSV export failed: \(error, privacy: .private)")
                }
            }
            .confirmationDialog(
                lang["settings.resetPrompt"],
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button(lang["settings.resetAll"], role: .destructive) { resetAll() }
                Button(lang["action.cancel"], role: .cancel) {}
            } message: {
                Text(lang["settings.resetMessage"])
            }
        }
    }

    private func handleDeepLink(_ section: String) {
        switch section {
        case "loans":       navPath.append("loans")
        case "creditlines": navPath.append("creditlines")
        case "recurring":   navPath.append("recurring")
        default:            break
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var languageSection: some View {
        Section(lang["settings.language.section"]) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    lang.setLanguage(language)
                } label: {
                    HStack {
                        Text(language.flag + "  " + language.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if lang.current == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var exchangeRatesSection: some View {
        Section(lang["fx.settings.section"]) {
            NavigationLink {
                ExchangeRateSettingsView()
            } label: {
                HStack {
                    Label(lang["fx.title"], systemImage: "arrow.left.arrow.right.circle")
                    Spacer()
                    if rateManager.isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else if rateManager.lastUpdated != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            NavigationLink {
                SubscriptionView()
            } label: {
                HStack {
                    Label(lang["entitlement.title"], systemImage: "star.circle.fill")
                    Spacer()
                    tierBadge
                }
            }
        }
    }

    @ViewBuilder
    private var bankSyncSection: some View {
        Section(lang["flinks.settings.section"]) {
            if entitlements.hasPaidTier {
                NavigationLink {
                    BankSyncDestinationView()
                } label: {
                    Label(bankSyncProviderLabel,
                          systemImage: "building.columns.badge.plus")
                }
            } else {
                HStack {
                    Label(bankSyncProviderLabel,
                          systemImage: "building.columns.badge.plus")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        Section(lang["security.title"]) {
            NavigationLink {
                SecuritySettingsView()
            } label: {
                Label(lang["security.title"], systemImage: "lock.shield")
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section(lang["notification.settings"]) {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label(lang["notification.manage"], systemImage: "bell.badge")
            }
        }
    }

    @ViewBuilder
    private var cloudSyncSection: some View {
        Section {
            if entitlements.hasPaidTier {
                Toggle(isOn: $cloudSyncEnabled) {
                    Label(lang["settings.cloudSync"], systemImage: "icloud.fill")
                }
                .onChange(of: cloudSyncEnabled) { _, _ in
                    showCloudRestartAlert = true
                }
            } else {
                HStack {
                    Label(lang["settings.cloudSync"], systemImage: "icloud.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(lang["settings.cloudSync.section"])
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entitlements.hasPaidTier
                     ? lang["settings.cloudSync.footer"]
                     : lang["settings.cloudSync.locked"])
                if let lastError = UserDefaults.standard.string(forKey: "fintrack.cloudSync.lastError") {
                    Text("\(lang["settings.cloudSync.lastError"]) \(lastError)")
                        .foregroundStyle(.orange)
                }
            }
        }
        .alert(lang["settings.cloudSync.restart.title"], isPresented: $showCloudRestartAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lang["settings.cloudSync.restart.body"])
        }
    }

    private var dataSection: some View {
        Section(lang["settings.data"]) {
            NavigationLink {
                CreditLinesView()
            } label: {
                Label(lang["cl.title"], systemImage: "creditcard.fill")
            }

            NavigationLink {
                SavingsProjectsView()
            } label: {
                Label(lang["savings.title"], systemImage: "target")
            }

            NavigationLink {
                LoansView()
            } label: {
                Label(lang["loan.title"], systemImage: "house.fill")
            }

            NavigationLink {
                RecurrencesView()
            } label: {
                Label(lang["recurring.title"], systemImage: "arrow.2.squarepath")
            }

            NavigationLink {
                ManageCategoriesView()
            } label: {
                Label(lang["category.manage"], systemImage: "tag")
            }

            Button {
                prepareExport()
            } label: {
                Label(lang["settings.exportCSV"], systemImage: "square.and.arrow.up")
            }
            .disabled(allTransactions.isEmpty)
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        Section(lang["settings.stats"]) {
            LabeledContent(lang["settings.accountCount"]) {
                Text("\(allAccounts.count)")
            }
            LabeledContent(lang["settings.txCount"]) {
                Text("\(allTransactions.count)")
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label(lang["settings.resetAll"], systemImage: "trash")
            }
        } header: {
            Text(lang["settings.dangerZone"])
        } footer: {
            Text(lang["settings.resetAll.footer"])
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section(lang["settings.about"]) {
            LabeledContent(lang["settings.version"]) {
                Text(appVersion)
            }
            LabeledContent(lang["settings.storage"]) {
                Text(lang["settings.storage.local"])
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private var developerSection: some View {
        let e = EntitlementManager.shared
        let tierName = e.hasPlacement ? "Placement" : e.hasPaidTier ? "Épargne" : "Courant"
        let tierColor: Color = e.hasPlacement ? .teal : e.hasPaidTier ? .orange : .gray

        Section {
            NavigationLink {
                DeveloperView()
            } label: {
                HStack {
                    Label("Développeur", systemImage: "hammer.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(tierName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tierColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(tierColor)
                }
            }
        }
        .listRowBackground(Color.orange.opacity(0.06))
    }
    #endif

    // MARK: - Tier badge

    private var tierBadge: some View {
        let label: String
        let color: Color
        switch entitlements.tier {
        case .free:
            label = "Free"
            color = .gray
        case .epargne:
            label = "Pro"
            color = .orange
        case .placement:
            label = "Plaid"
            color = .teal
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var defaultExportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "fintrack-export-\(formatter.string(from: .now))"
    }

    private func prepareExport() {
        let csv = CSVExporter.exportTransactions(allTransactions)
        exportDocument = CSVDocument(text: csv)
        showExporter = true
    }

    private func resetAll() {
        // Delete all transactions, accounts, and user-created categories.
        for tx in allTransactions { context.delete(tx) }
        for acc in allAccounts { context.delete(acc) }
        let userCategories = (try? context.fetch(
            FetchDescriptor<Category>(predicate: #Predicate { !$0.isSystem })
        )) ?? []
        for cat in userCategories { context.delete(cat) }

        // Optionally also wipe system categories so seed will regenerate clean.
        let systemCategories = (try? context.fetch(
            FetchDescriptor<Category>(predicate: #Predicate { $0.isSystem })
        )) ?? []
        for cat in systemCategories { context.delete(cat) }

        try? context.save()
        SeedData.seedIfNeeded(context: context)
    }
}

// MARK: - CSV export

enum CSVExporter {
    static func exportTransactions(_ transactions: [Transaction]) -> String {
        let header = "date,type,amount,currency,account,institution,category,payee,note\n"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let rows: [String] = transactions.map { tx in
            [
                iso.string(from: tx.date),
                tx.type.rawValue,
                "\(tx.amount)",
                tx.account?.currency ?? "",
                escape(tx.account?.name ?? ""),
                escape(tx.account?.institution ?? ""),
                escape(tx.category?.localizedName ?? ""),
                escape(tx.payee ?? ""),
                escape(tx.note)
            ].joined(separator: ",")
        }
        return header + rows.joined(separator: "\n")
    }

    /// CSV escape + formula injection protection (OWASP CSV Injection).
    /// Characters =, +, -, @, \t, \r at the start of a field can trigger
    /// macro execution in Excel/LibreOffice. We prefix them with an apostrophe.
    private static func escape(_ s: String) -> String {
        var result = s
        // Neutralise formula injection
        let formulaStarters: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]
        if let first = result.first, formulaStarters.contains(first) {
            result = "'" + result
        }
        // Standard RFC 4180 quoting
        if result.contains(",") || result.contains("\"") || result.contains("\n") {
            let escaped = result.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return result
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - Manage categories

struct ManageCategoriesView: View {
    @Environment(\.modelContext) private var context

    @Environment(LanguageManager.self) private var lang
    @Query(sort: \Category.name, order: .forward) private var categories: [Category]

    @State private var showAddCategory = false

    private var expenseCategories: [Category] {
        categories.filter { $0.applicability == .expense || $0.applicability == .both }
    }
    private var incomeCategories: [Category] {
        categories.filter { $0.applicability == .income || $0.applicability == .both }
    }

    var body: some View {
        List {
            Section(lang.f("category.expenses", expenseCategories.count)) {
                ForEach(expenseCategories) { cat in
                    categoryRow(cat)
                }
                .onDelete { offsets in delete(expenseCategories, at: offsets) }
            }
            Section(lang.f("category.incomes", incomeCategories.count)) {
                ForEach(incomeCategories) { cat in
                    categoryRow(cat)
                }
                .onDelete { offsets in delete(incomeCategories, at: offsets) }
            }
        }
        .navigationTitle(lang["category.title"])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategoryView()
        }
    }

    private func categoryRow(_ cat: Category) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: cat.colorHex).opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: cat.iconSystemName)
                    .foregroundStyle(Color(hex: cat.colorHex))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.localizedName)
                if cat.isSystem {
                    Text(lang["category.default"])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\((cat.transactions ?? []).count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func delete(_ items: [Category], at offsets: IndexSet) {
        for index in offsets {
            let cat = items[index]
            // System categories: just hide.
            if cat.isSystem {
                cat.isHidden = true
            } else {
                context.delete(cat)
            }
        }
        try? context.save()
    }
}

struct AddCategoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    @State private var name: String = ""
    @State private var applicability: CategoryApplicability = .expense
    @State private var iconSystemName: String = "tag.fill"
    @State private var colorHex: String = ColorPalette.categoryColors.first ?? "#3478F6"

    private let iconChoices = [
        "tag.fill", "cart.fill", "fork.knife", "car.fill", "house.fill",
        "bolt.fill", "cross.case.fill", "film.fill", "tshirt.fill", "book.fill",
        "airplane", "gift.fill", "building.columns", "doc.text.fill", "globe",
        "briefcase.fill", "star.fill", "heart.fill", "leaf.fill", "pawprint.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(lang["label.name"]) {
                    TextField(lang["category.namePlaceholder"], text: $name)
                }
                Section(lang["category.type"]) {
                    Picker(lang["category.applicability"], selection: $applicability) {
                        Text(lang["category.expense"]).tag(CategoryApplicability.expense)
                        Text(lang["category.income"]).tag(CategoryApplicability.income)
                        Text(lang["category.both"]).tag(CategoryApplicability.both)
                    }
                    .pickerStyle(.segmented)
                }
                Section(lang["label.icon"]) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(iconChoices, id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.system(size: 18))
                                    .frame(width: 40, height: 40)
                                    .background(
                                        icon == iconSystemName
                                            ? Color(hex: colorHex)
                                            : Color(.tertiarySystemBackground),
                                        in: Circle()
                                    )
                                    .foregroundStyle(icon == iconSystemName ? .white : .primary)
                                    .onTapGesture { iconSystemName = icon }
                            }
                        }
                    }
                }
                Section(lang["label.color"]) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ColorPalette.categoryColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if hex == colorHex {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                    }
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                    }
                }
            }
            .navigationTitle(lang["category.create"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let cat = Category(
            name: name.trimmingCharacters(in: .whitespaces),
            iconSystemName: iconSystemName,
            colorHex: colorHex,
            applicability: applicability,
            isSystem: false
        )
        context.insert(cat)
        try? context.save()
        dismiss()
    }
}
