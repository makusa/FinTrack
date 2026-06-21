//
//  ManageHubView.swift
//  FinTrack
//
//  "Gérer" tab — a single home for every data type that used to be split
//  between the Budgets tab and Settings ▸ Data. Settings is now app config only.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ManageHubView: View {
    @Binding var deepLink: String

    @Environment(LanguageManager.self) private var lang
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var navPath = NavigationPath()
    @State private var showExporter = false
    @State private var exportDocument = CSVDocument(text: "")

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section(lang["manage.planning"]) {
                    NavigationLink {
                        BudgetsView()
                    } label: {
                        Label(lang["budget.title"], systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        SavingsProjectsView()
                    } label: {
                        Label(lang["savings.title"], systemImage: "target")
                    }
                    NavigationLink {
                        RecurrencesView()
                    } label: {
                        Label(lang["recurring.title"], systemImage: "arrow.2.squarepath")
                    }
                }

                Section(lang["manage.products"]) {
                    NavigationLink {
                        LoansView()
                    } label: {
                        Label(lang["loan.title"], systemImage: "house.fill")
                    }
                    NavigationLink {
                        CreditLinesView()
                    } label: {
                        Label(lang["cl.title"], systemImage: "creditcard.fill")
                    }
                    NavigationLink {
                        RegisteredAccountsView()
                    } label: {
                        Label(lang["reg.hub.title"], systemImage: "leaf.fill")
                    }
                }

                Section(lang["manage.organization"]) {
                    NavigationLink {
                        ManageCategoriesView()
                    } label: {
                        Label(lang["category.manage"], systemImage: "tag")
                    }
                    NavigationLink {
                        ProGated(feature: .fileImport) {
                            OFXImportView()
                        }
                    } label: {
                        Label(lang["import.ofx.title"], systemImage: "arrow.down.doc")
                    }
                    Button {
                        prepareExport()
                    } label: {
                        Label(lang["settings.exportCSV"], systemImage: "square.and.arrow.up")
                    }
                    .disabled(allTransactions.isEmpty)
                }
            }
            .navigationTitle(lang["tab.manage"])
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
}
