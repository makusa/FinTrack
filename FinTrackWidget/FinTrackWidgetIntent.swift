//  FinTrackWidgetIntent.swift — Configurable widget content selector (iOS 17+)
//  The FinTrack widget lets the user pick what to show via long-press → Edit.
//  Add cases here as new content types ship (balances, savings, registered…).
import WidgetKit
import AppIntents

/// What the configurable FinTrack widget shows.
enum WidgetContentType: String, AppEnum {
    case netWorth
    case budgets
    case balances
    case savings
    case registered

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "FinTrack content")
    static var caseDisplayRepresentations: [WidgetContentType: DisplayRepresentation] = [
        .netWorth: DisplayRepresentation(title: "Net Worth"),
        .budgets:  DisplayRepresentation(title: "Budgets"),
        .balances: DisplayRepresentation(title: "Account Balances"),
        .savings:  DisplayRepresentation(title: "Savings Goals"),
        .registered: DisplayRepresentation(title: "Registered Accounts"),
    ]
}

struct SelectContentIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget content"
    static var description = IntentDescription("Choose what the widget shows.")

    @Parameter(title: "Show", default: .netWorth)
    var content: WidgetContentType

    init() {}
}
