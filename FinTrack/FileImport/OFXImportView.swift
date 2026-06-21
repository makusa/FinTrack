//
//  OFXImportView.swift
//  FinTrack
//
//  Mandatory import preview for OFX/QFX statements:
//    pick file → parse → suggest target account → review (include/exclude) →
//    commit through TransactionReconciler → result summary.
//  No internal NavigationStack: the caller (Gérer ▸ Organisation) wraps/pushes.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct OFXImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    private enum Phase { case pick, mapping, preview, done }
    @State private var phase: Phase = .pick
    @State private var showImporter = false
    @State private var parseError: String?

    @State private var statement: OFXStatement?
    @State private var rows: [DraftRow] = []
    @State private var selectedUuid: String?
    @State private var confidence: AccountSuggestion.Confidence = .none
    @State private var outcome: TransactionReconciler.Outcome?
    @State private var csvResult: CSVParseResult?

    struct DraftRow: Identifiable {
        let id = UUID()
        let txn: OFXTransaction
        var include: Bool = true
    }

    /// .qfx / .ofx / .csv by extension; .data as a permissive fallback. The
    /// picked file is routed to the OFX or CSV path by extension + content sniff;
    /// each parser validates and rejects unsupported content with a clear message.
    private static let acceptedTypes: [UTType] = {
        var t: [UTType] = []
        if let q = UTType(filenameExtension: "qfx") { t.append(q) }
        if let o = UTType(filenameExtension: "ofx") { t.append(o) }
        t.append(.commaSeparatedText)
        t.append(.data)
        return t
    }()

    var body: some View {
        Group {
            switch phase {
            case .pick:    pickPhase
            case .mapping: mappingPhase
            case .preview: previewPhase
            case .done:    donePhase
            }
        }
        .navigationTitle(lang["import.ofx.title"])
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: Self.acceptedTypes,
                      allowsMultipleSelection: false) { handlePicked($0) }
    }

    // MARK: - Pick

    private var pickPhase: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(lang["import.ofx.intro"])
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if let err = parseError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if accounts.isEmpty {
                Text(lang["import.ofx.noAccounts"])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Button {
                    parseError = nil
                    showImporter = true
                } label: {
                    Label(lang["import.ofx.pick"], systemImage: "folder")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Preview

    private var previewPhase: some View {
        List {
            accountSection
            if let warning = currencyWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach($rows) { $row in
                    rowView($row)
                }
            } header: {
                HStack {
                    Text(lang.f("import.ofx.section.transactions", includedCount))
                    Spacer()
                    Button(allIncluded ? lang["import.ofx.excludeAll"]
                                       : lang["import.ofx.includeAll"]) {
                        let v = !allIncluded
                        for i in rows.indices { rows[i].include = v }
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { importBar }
    }

    private var accountSection: some View {
        Section {
            Picker(lang["import.ofx.account"], selection: $selectedUuid) {
                ForEach(accounts) { acc in
                    Text(acc.name).tag(Optional(acc.uuid))
                }
            }
            if confidence == .weak || confidence == .none {
                Label(lang["import.ofx.confirmAccount"], systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(lang["import.ofx.account"])
        } footer: {
            if let st = statement {
                Text(lang.f("import.ofx.detected",
                            st.currency ?? "—",
                            st.transactions.count))
            }
        }
    }

    private func rowView(_ row: Binding<DraftRow>) -> some View {
        let t = row.wrappedValue.txn
        let on = row.wrappedValue.include
        return HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(t))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(dateText(t.datePosted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText(t))
                .font(.body.weight(.semibold))
                .foregroundStyle(t.amount > 0 ? Color.green : Color.primary)
        }
        .opacity(on ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { row.wrappedValue.include.toggle() }
    }

    private var importBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                performImport()
            } label: {
                Text(lang.f("import.ofx.import", includedCount))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedUuid == nil || includedCount == 0)
            .padding()
        }
        .background(.bar)
    }

    // MARK: - Done

    private var donePhase: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text(lang["import.ofx.result.title"])
                .font(.title2.weight(.semibold))
            if let o = outcome {
                VStack(alignment: .leading, spacing: 10) {
                    resultLine(lang["import.ofx.result.added"], o.added)
                    if o.reconciled > 0 { resultLine(lang["import.ofx.result.reconciled"], o.reconciled) }
                    if o.flagged > 0    { resultLine(lang["import.ofx.result.flagged"], o.flagged) }
                    if o.skipped > 0    { resultLine(lang["import.ofx.result.skipped"], o.skipped) }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)
            }
            Spacer()
            Button(lang["action.close"]) { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func resultLine(_ label: String, _ n: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(n)").fontWeight(.semibold)
        }
    }

    // MARK: - Logic

    private var selectedAccount: Account? {
        accounts.first { $0.uuid == selectedUuid }
    }
    private var includedCount: Int { rows.filter { $0.include }.count }
    private var allIncluded: Bool { !rows.isEmpty && rows.allSatisfy { $0.include } }

    private var currencyWarning: String? {
        guard let st = statement, let cur = st.currency,
              let acc = selectedAccount, acc.currency != cur else { return nil }
        return lang.f("import.ofx.currencyMismatch", cur, acc.currency)
    }

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            parseError = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if isCSVFile(url: url, data: data) {
                    try handleCSV(data)
                } else {
                    try handleOFX(data)
                }
                parseError = nil
            } catch let e as OFXParseError {
                parseError = friendlyOFX(e)
            } catch let e as CSVImportError {
                parseError = friendlyCSV(e)
            } catch {
                parseError = error.localizedDescription
            }
        }
    }

    private func handleOFX(_ data: Data) throws {
        presentStatement(try OFXParser.parse(data))
    }

    private func handleCSV(_ data: Data) throws {
        let result = try CSVImporter.parse(data)
        csvResult = result
        let colCount = (result.header?.count) ?? (result.rows.map { $0.count }.max() ?? 0)
        if let remembered = CSVMappingStore.remembered(forHeader: result.header, columnCount: colCount),
           remembered.dateIndex != nil, remembered.hasAmount {
            presentStatement(CSVImporter.buildStatement(rows: result.rows, mapping: remembered, source: "csv"))
        } else {
            phase = .mapping
        }
    }

    private func applyCSVMapping(_ mapping: CSVColumnMapping) {
        guard let result = csvResult else { return }
        let colCount = (result.header?.count) ?? (result.rows.map { $0.count }.max() ?? 0)
        CSVMappingStore.remember(mapping, forHeader: result.header, columnCount: colCount)
        presentStatement(CSVImporter.buildStatement(rows: result.rows, mapping: mapping, source: "csv"))
    }

    /// Shared entry into the review screen for both OFX and post-mapping CSV.
    private func presentStatement(_ st: OFXStatement) {
        let suggestion = OFXImportService.suggestAccount(for: st, among: accounts)
        statement = st
        rows = st.transactions.map { DraftRow(txn: $0) }
        selectedUuid = suggestion.accountUuid ?? accounts.first?.uuid
        confidence = suggestion.confidence
        phase = .preview
    }

    private func isCSVFile(url: URL, data: Data) -> Bool {
        switch url.pathExtension.lowercased() {
        case "qfx", "ofx": return false
        case "csv", "tsv", "txt": return true
        default:
            let head = String(decoding: data.prefix(512), as: UTF8.self).uppercased()
            return !head.contains("<OFX")
        }
    }

    private func performImport() {
        guard let st = statement, let acc = selectedAccount else { return }
        let included = rows.filter { $0.include }.map { $0.txn }
        guard !included.isEmpty else { return }
        var filtered = st
        filtered.transactions = included
        outcome = OFXImportService.commit(statement: filtered, into: acc, context: context)
        phase = .done
    }

    private func friendlyOFX(_ e: OFXParseError) -> String {
        switch e {
        case .notOFX:         return lang["import.ofx.error.notOFX"]
        case .noTransactions: return lang["import.ofx.error.empty"]
        case .undecodable:    return lang["import.ofx.error.undecodable"]
        }
    }

    private func friendlyCSV(_ e: CSVImportError) -> String {
        switch e {
        case .empty:          return lang["import.csv.error.empty"]
        case .noDateColumn:   return lang["import.csv.error.noDate"]
        case .noAmountColumn: return lang["import.csv.error.noAmount"]
        case .undecodable:    return lang["import.ofx.error.undecodable"]
        }
    }

    // MARK: - Mapping (CSV)

    @ViewBuilder private var mappingPhase: some View {
        if let result = csvResult {
            CSVMappingView(result: result) { mapping in applyCSVMapping(mapping) }
        } else {
            pickPhase
        }
    }

    // MARK: - Formatting

    private func amountText(_ t: OFXTransaction) -> String {
        let code = statement?.currency ?? selectedAccount?.currency ?? Currencies.default
        let prefix = t.amount > 0 ? "+" : "−"
        return prefix + abs(t.amount).formatted(asCurrency: code)
    }

    private func dateText(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func rowTitle(_ t: OFXTransaction) -> String {
        t.name ?? t.memo ?? lang["import.ofx.row.untitled"]
    }
}

#Preview {
    NavigationStack {
        OFXImportView()
    }
    .environment(LanguageManager.shared)
    .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
}
