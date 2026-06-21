//
//  CSVMappingView.swift
//  FinTrack
//
//  Lets the user confirm/correct how a CSV's columns map to date / amount /
//  description before the transactions reach the shared review screen. Pre-filled
//  from auto-detection; shown only on the first import of a given layout (repeat
//  imports reuse the remembered mapping and skip straight to the preview).
//

import SwiftUI

struct CSVMappingView: View {
    let result: CSVParseResult
    let onContinue: (CSVColumnMapping) -> Void

    @Environment(LanguageManager.self) private var lang

    private enum AmountMode: Hashable { case signed, pair }

    private let columns: [Int]
    private let showDateOrderChoice: Bool

    @State private var dateIndex: Int?
    @State private var amountMode: AmountMode
    @State private var amountIndex: Int?
    @State private var debitIndex: Int?
    @State private var creditIndex: Int?
    @State private var descIndex: Int?
    @State private var dayFirst: Bool

    init(result: CSVParseResult, onContinue: @escaping (CSVColumnMapping) -> Void) {
        self.result = result
        self.onContinue = onContinue
        let m = result.mapping
        let colCount = (result.header?.count) ?? (result.rows.map { $0.count }.max() ?? 0)
        self.columns = Array(0..<max(colCount, 0))
        self.showDateOrderChoice = m.dateOrderAssumed
        _dateIndex = State(initialValue: m.dateIndex)
        _amountMode = State(initialValue: m.amountIndex != nil ? .signed : .pair)
        _amountIndex = State(initialValue: m.amountIndex)
        _debitIndex = State(initialValue: m.debitIndex)
        _creditIndex = State(initialValue: m.creditIndex)
        _descIndex = State(initialValue: m.descriptionIndices.first)
        _dayFirst = State(initialValue: m.dateFormat != .monthFirst)
    }

    var body: some View {
        Form {
            Section {
                Text(lang["import.csv.intro"]).font(.subheadline).foregroundStyle(.secondary)
            }

            Section(lang["import.csv.section.columns"]) {
                Picker(lang["import.csv.col.date"], selection: $dateIndex) {
                    ForEach(columns, id: \.self) { Text(columnLabel($0)).tag(Optional($0)) }
                }
                Picker(lang["import.csv.amountMode"], selection: $amountMode) {
                    Text(lang["import.csv.amountMode.signed"]).tag(AmountMode.signed)
                    Text(lang["import.csv.amountMode.pair"]).tag(AmountMode.pair)
                }
                .pickerStyle(.segmented)
                if amountMode == .signed {
                    Picker(lang["import.csv.col.amount"], selection: $amountIndex) {
                        ForEach(columns, id: \.self) { Text(columnLabel($0)).tag(Optional($0)) }
                    }
                } else {
                    Picker(lang["import.csv.col.debit"], selection: $debitIndex) {
                        Text(lang["import.csv.col.none"]).tag(Optional<Int>.none)
                        ForEach(columns, id: \.self) { Text(columnLabel($0)).tag(Optional($0)) }
                    }
                    Picker(lang["import.csv.col.credit"], selection: $creditIndex) {
                        Text(lang["import.csv.col.none"]).tag(Optional<Int>.none)
                        ForEach(columns, id: \.self) { Text(columnLabel($0)).tag(Optional($0)) }
                    }
                }
                Picker(lang["import.csv.col.description"], selection: $descIndex) {
                    Text(lang["import.csv.col.none"]).tag(Optional<Int>.none)
                    ForEach(columns, id: \.self) { Text(columnLabel($0)).tag(Optional($0)) }
                }
            }

            if showDateOrderChoice {
                Section(lang["import.csv.dateOrder"]) {
                    Picker(lang["import.csv.dateOrder"], selection: $dayFirst) {
                        Text(lang["import.csv.dateOrder.dayFirst"]).tag(true)
                        Text(lang["import.csv.dateOrder.monthFirst"]).tag(false)
                    }
                    .pickerStyle(.segmented)
                    if let ex = dateExample {
                        Text(ex).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section(lang["import.csv.section.preview"]) {
                let txns = previewTxns
                if txns.isEmpty {
                    Text(lang["import.csv.previewEmpty"]).font(.footnote).foregroundStyle(.orange)
                } else {
                    ForEach(Array(txns.enumerated()), id: \.offset) { _, t in previewRow(t) }
                }
            }
        }
        .navigationTitle(lang["import.csv.title"])
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { onContinue(currentMapping) } label: {
                Text(lang["import.csv.continue"])
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canContinue ? Color.accentColor : Color.gray.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .disabled(!canContinue)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    // MARK: Derived state

    private var resolvedDateFormat: CSVDateFormat {
        if showDateOrderChoice { return dayFirst ? .dayFirst : .monthFirst }
        return result.mapping.dateFormat
    }

    private var currentMapping: CSVColumnMapping {
        CSVColumnMapping(
            dateIndex: dateIndex,
            amountIndex: amountMode == .signed ? amountIndex : nil,
            debitIndex: amountMode == .pair ? debitIndex : nil,
            creditIndex: amountMode == .pair ? creditIndex : nil,
            descriptionIndices: descIndex.map { [$0] } ?? [],
            dateFormat: resolvedDateFormat,
            dateOrderAssumed: false)
    }

    private var canContinue: Bool {
        guard dateIndex != nil else { return false }
        return amountMode == .signed ? amountIndex != nil : (debitIndex != nil || creditIndex != nil)
    }

    private var previewTxns: [OFXTransaction] {
        let st = CSVImporter.buildStatement(rows: Array(result.rows.prefix(5)),
                                            mapping: currentMapping, source: "csv")
        return Array(st.transactions.prefix(4))
    }

    private var dateExample: String? {
        guard let di = dateIndex,
              let raw = result.rows.compactMap({ di < $0.count ? $0[di] : nil })
                  .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let date = CSVDate.parse(raw, format: resolvedDateFormat) else { return nil }
        return lang.f("import.csv.dateExample", raw.trimmingCharacters(in: .whitespaces), formatted(date))
    }

    // MARK: Rows

    @ViewBuilder private func previewRow(_ t: OFXTransaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name ?? "—").font(.subheadline).lineLimit(1)
                Text(formatted(t.datePosted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(signedAmountString(t.amount))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(t.amount < 0 ? Color.primary : Color.green)
        }
    }

    private func columnLabel(_ i: Int) -> String {
        if let h = result.header, i < h.count {
            let t = h[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return lang.f("import.csv.col.generic", i + 1)
    }

    private func formatted(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func signedAmountString(_ amount: Decimal) -> String {
        let prefix = amount < 0 ? "\u{2212}" : "+"
        return prefix + abs(amount).formatted(.number.precision(.fractionLength(2)))
    }
}
