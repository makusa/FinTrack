//
//  BankPicker.swift
//  FinTrack
//
//  Three composable pieces:
//    • BankLogoView           — async logo from Clearbit, SF Symbol fallback
//    • InstitutionPickerField — drop-in replacement for a plain institution TextField
//    • BankPickerSheet        — searchable full-screen bank browser
//

import SwiftUI

// MARK: - BankLogoView

/// Loads the official bank logo from logo.clearbit.com.
/// Falls back gracefully to a generic banking SF Symbol.
struct BankLogoView: View {
    let domain: String?
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil  // nil = size * 0.22

    private var url: URL? { BankDirectory.logoURL(for: domain) }
    private var radius: CGFloat { cornerRadius ?? size * 0.22 }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFit()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
            Image(systemName: "building.columns.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - InstitutionPickerField

/// Replaces a plain TextField for institution input.
/// Shows the matched bank logo inline; a search button opens the full picker.
/// The user can also type freely — no bank in the directory is required.
struct InstitutionPickerField: View {
    @Binding var text: String
    var placeholder: String = "Institution"

    @State private var showPicker = false

    private var matchedDomain: String? { BankDirectory.domain(for: text) }

    var body: some View {
        HStack(spacing: 10) {
            // Logo or generic icon
            BankLogoView(domain: matchedDomain, size: 28, cornerRadius: 6)

            // Free-form text field
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()

            // Tap to browse picker
            Button {
                showPicker = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tint)
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            BankPickerSheet(selectedName: $text)
        }
    }
}

// MARK: - BankPickerSheet

struct BankPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    @Binding var selectedName: String

    @State private var query: String = ""

    // Preferred country order for sections
    private let preferredOrder = ["CA", "US", "GB", "FR", "DE", "ES", "PT", "NL", "BE", "CH", "AF", "INT"]

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchResults: [BankInfo] { BankDirectory.search(query) }

    private var countries: [String] {
        preferredOrder.filter { code in
            !BankDirectory.banks(for: code).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    if searchResults.isEmpty {
                        // Allow using the raw typed text as-is
                        Section {
                            Button {
                                selectedName = query.trimmingCharacters(in: .whitespaces)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.tint)
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(query.trimmingCharacters(in: .whitespaces))
                                            .foregroundStyle(.primary)
                                        Text(lang["bank.useCustom"])
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Section {
                            ForEach(searchResults) { bank in
                                bankRow(bank)
                            }
                        }
                    }
                } else {
                    // Browsing mode: sections by country
                    ForEach(countries, id: \.self) { code in
                        Section {
                            ForEach(BankDirectory.banks(for: code)) { bank in
                                bankRow(bank)
                            }
                        } header: {
                            Text(BankDirectory.flag(for: code) + "  " + BankDirectory.countryName(for: code))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(lang["label.institution"])
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: lang["action.search"])
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func bankRow(_ bank: BankInfo) -> some View {
        Button {
            selectedName = bank.name
            dismiss()
        } label: {
            HStack(spacing: 12) {
                BankLogoView(domain: bank.domain, size: 36, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let alias = bank.aliases.first {
                        Text(alias.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if bank.name == selectedName {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
