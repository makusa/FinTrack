//
//  RegisteredRoomPlanView.swift
//  FinTrack
//
//  Editor for a registered-account room ANCHOR (RegisteredRoomPlan).
//  The user enters the contribution room reported by the CRA as of Jan 1 of a
//  chosen year; the engine projects forward. One plan per type, per person.
//

import SwiftUI
import SwiftData

struct RegisteredRoomPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    let type: RegisteredType
    let existing: RegisteredRoomPlan?

    @State private var anchorYear: Int
    @State private var anchorAmountText: String
    @State private var lifetimeContributedText: String

    init(type: RegisteredType, existing: RegisteredRoomPlan?) {
        self.type = type
        self.existing = existing
        let yr = existing?.anchorYear ?? Calendar.current.component(.year, from: .now)
        _anchorYear = State(initialValue: yr)
        let amt = existing?.anchorAmount ?? 0
        _anchorAmountText = State(initialValue: amt == 0 ? "" : amt.appFormattedForInput)
        let life = existing?.lifetimeContributedAtAnchor ?? 0
        _lifetimeContributedText = State(initialValue: life == 0 ? "" : life.appFormattedForInput)
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    /// CRA room figures are unreliable Jan–Apr (prior-year activity not yet posted).
    private var isLagWindow: Bool {
        (1...4).contains(Calendar.current.component(.month, from: .now))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(lang["reg.anchor.year"], selection: $anchorYear) {
                        ForEach((2009...currentYear).reversed(), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    HStack {
                        Text(lang["reg.anchor.amount"])
                        Spacer()
                        TextField("0", text: $anchorAmountText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text(Currencies.info(for: "CAD").symbol).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(lang["reg.anchor.section"])
                } footer: {
                    Text(lang["reg.anchor.footer"])
                }

                if type == .celiapp {
                    Section {
                        HStack {
                            Text(lang["reg.anchor.lifetimeContributed"])
                            Spacer()
                            TextField("0", text: $lifetimeContributedText)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 140)
                            Text(Currencies.info(for: "CAD").symbol).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text(lang["reg.anchor.lifetimeFooter"])
                    }
                }

                if isLagWindow {
                    Section {
                        Label(lang["reg.anchor.lagWarning"], systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(type.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let amount = parseDecimal(anchorAmountText) ?? 0
        let lifetime = type == .celiapp ? (parseDecimal(lifetimeContributedText) ?? 0) : 0
        if let plan = existing {
            plan.anchorYear = anchorYear
            plan.anchorAmount = amount
            plan.lifetimeContributedAtAnchor = lifetime
            plan.anchorSetInLagWindow = isLagWindow
        } else {
            let plan = RegisteredRoomPlan(
                registeredType: type,
                anchorYear: anchorYear,
                anchorAmount: amount,
                lifetimeContributedAtAnchor: lifetime,
                anchorSetInLagWindow: isLagWindow
            )
            context.insert(plan)
        }
        try? context.save()
        dismiss()
    }

    private func parseDecimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces))
    }
}
