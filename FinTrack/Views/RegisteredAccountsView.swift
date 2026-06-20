//
//  RegisteredAccountsView.swift
//  FinTrack
//
//  Hub (in Settings) for registered-account contribution room. The room ANCHOR
//  is per person per type — it lives here, independent of any single account.
//  Shows available room per type (aggregated across all accounts of that type)
//  and hosts the anchor editor.
//

import SwiftUI
import SwiftData

struct RegisteredAccountsView: View {
    @Environment(LanguageManager.self) private var lang

    @Query private var allPlans: [RegisteredRoomPlan]
    @Query private var allAccounts: [Account]

    @State private var editingType: RegisteredType?

    /// Types the user can manage here (REER pending its income-based calc).
    private let types: [RegisteredType] = [.celi, .celiapp]

    private func plan(for type: RegisteredType) -> RegisteredRoomPlan? {
        allPlans.first { $0.registeredType == type }
    }

    private func accountCount(_ type: RegisteredType) -> Int {
        allAccounts.filter { $0.registeredProfile?.registeredType == type }.count
    }

    var body: some View {
        List {
            ForEach(types) { type in
                Section {
                    if let plan = plan(for: type),
                       let result = RegisteredRoomService.availableRoom(type: type, plan: plan, accounts: allAccounts) {
                        LabeledContent(lang["reg.room.available"]) {
                            Text(result.availableRoom.formatted(asCurrency: "CAD"))
                                .fontWeight(.semibold)
                                .foregroundStyle(result.isOverContributed ? Color.red : Color.primary)
                        }
                        if result.isOverContributed {
                            Label("\(lang["reg.room.over"]) : \(result.excess.formatted(asCurrency: "CAD"))",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                        LabeledContent(lang["reg.anchor.label"]) {
                            Text("\(plan.anchorAmount.formatted(asCurrency: "CAD")) · \(String(plan.anchorYear))")
                        }
                        Button(lang["reg.anchor.edit"]) { editingType = type }
                    } else {
                        Button {
                            editingType = type
                        } label: {
                            Label(lang["reg.room.configure"], systemImage: "slider.horizontal.3")
                        }
                    }
                } header: {
                    Text(type.label)
                } footer: {
                    Text(accountCount(type) == 0 ? lang["reg.hub.noAccounts"] : lang["reg.room.sharedFooter"])
                }
            }
        }
        .navigationTitle(lang["reg.hub.title"])
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingType) { type in
            RegisteredRoomPlanView(type: type, existing: plan(for: type))
        }
    }
}
