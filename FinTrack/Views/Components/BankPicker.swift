//
//  BankPicker.swift
//  FinTrack
//
//  Three composable pieces:
//    • BankLogoView           — multi-source logo loader with in-memory cache
//    • InstitutionPickerField — drop-in replacement for a plain institution TextField
//    • BankPickerSheet        — searchable full-screen bank browser
//
//  Logo sources tried in order (first success wins):
//    1. logo.clearbit.com/{domain}          — high quality, unreliable since HubSpot acquisition
//    2. www.google.com/s2/favicons?domain=  — always returns something, lower resolution
//    3. SF Symbol fallback (no network)     — always works
//

import SwiftUI

// MARK: - Logo image cache

/// Shared in-memory cache so logos aren't re-fetched every time a view appears.
final class BankLogoCache {
    static let shared = BankLogoCache()
    private init() {}

    private var cache: [String: UIImage] = [:]
    private let queue = DispatchQueue(label: "BankLogoCache", attributes: .concurrent)

    func get(_ key: String) -> UIImage? {
        queue.sync { cache[key] }
    }

    func set(_ key: String, image: UIImage) {
        queue.async(flags: .barrier) { self.cache[key] = image }
    }
}

// MARK: - BankLogoView

/// Loads the official bank logo from multiple sources with graceful fallback.
struct BankLogoView: View {
    let domain: String?
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil

    @State private var logoImage: UIImage? = nil
    @State private var failed = false

    private var radius: CGFloat { cornerRadius ?? size * 0.22 }

    // URLs to try in order
    private var candidateURLs: [URL] {
        guard let d = domain, !d.isEmpty else { return [] }
        return [
            // 1. Clearbit (best quality when it works)
            URL(string: "https://logo.clearbit.com/\(d)?size=128"),
            // 2. Google favicon (reliable, lower res)
            URL(string: "https://www.google.com/s2/favicons?domain=\(d)&sz=128"),
        ].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            if let img = logoImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else if failed || domain == nil {
                fallbackView
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
                    .overlay(
                        ProgressView().scaleEffect(0.6)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: domain) {
            await loadLogo()
        }
    }

    private var fallbackView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
            Image(systemName: "building.columns.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: Loading logic

    @MainActor
    private func loadLogo() async {
        guard let d = domain, !d.isEmpty else { failed = true; return }

        // Check cache first
        if let cached = BankLogoCache.shared.get(d) {
            logoImage = cached
            return
        }

        // Try each URL in sequence
        for url in candidateURLs {
            if let img = await fetchImage(from: url) {
                BankLogoCache.shared.set(d, image: img)
                logoImage = img
                return
            }
        }

        // All sources failed
        failed = true
    }

    private func fetchImage(from url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // A browser-like User-Agent helps with some CDN policies
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let img = UIImage(data: data),
              img.size.width > 10   // ignore 1×1 placeholder pixels
        else { return nil }
        return img
    }
}

// MARK: - InstitutionPickerField

/// Drop-in replacement for a plain TextField.
/// Shows the matched bank logo inline; a search button opens the full picker.
/// The user can also type freely — no bank match is required.
struct InstitutionPickerField: View {
    @Binding var text: String
    var placeholder: String = "Institution"
    /// Called when the user selects a known bank from the picker.
    /// Provides the matched BankInfo so the caller can set the logo domain etc.
    var onBankSelected: ((BankInfo) -> Void)? = nil
    /// Restricts the picker to free-tier institutions (CA + US) when false.
    var hasPro: Bool = true

    @State private var showPicker = false

    private var matchedDomain: String? { BankDirectory.domain(for: text) }

    var body: some View {
        HStack(spacing: 10) {
            BankLogoView(domain: matchedDomain, size: 28, cornerRadius: 6)

            TextField(placeholder, text: $text)
                .autocorrectionDisabled()

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
            BankPickerSheet(
                selectedName: $text,
                hasPro: hasPro,
                onBankSelected: onBankSelected
            )
        }
    }
}

// MARK: - BankPickerSheet

struct BankPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    @Binding var selectedName: String
    var hasPro: Bool = true
    var onBankSelected: ((BankInfo) -> Void)? = nil

    @State private var query: String = ""

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var searchResults: [BankInfo] { BankDirectory.search(query, hasPro: hasPro) }
    private var countries: [String] { BankDirectory.availableCountries(hasPro: hasPro) }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    if searchResults.isEmpty {
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
                    ForEach(countries, id: \.self) { code in
                        Section {
                            ForEach(BankDirectory.banks(for: code, hasPro: hasPro)) { bank in
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
            selectedName = bank.localizedName
            onBankSelected?(bank)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                BankLogoView(domain: bank.domain, size: 36, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.localizedName)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let alias = bank.aliases.first {
                        Text(alias.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if bank.localizedName == selectedName || bank.name == selectedName {
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
