//
//  TransactionStatusBadge.swift
//  FinTrack
//
//  Small pill showing a transaction's lifecycle status, or a possible-duplicate
//  warning. Colors live here (view layer); labels/icons come from the model.
//

import SwiftUI

struct TransactionStatusBadge: View {
    @Environment(LanguageManager.self) private var lang

    let status: TransactionStatus
    var needsReview: Bool = false

    private var color: Color {
        if needsReview { return .orange }
        switch status {
        case .scheduled:  return .blue
        case .pending:    return .orange
        case .cleared:    return .secondary
        case .reconciled: return .green
        case .skipped:    return .gray
        }
    }

    private var icon: String {
        needsReview ? "exclamationmark.triangle.fill" : status.iconSystemName
    }

    private var text: String {
        needsReview ? lang["tx.badge.duplicate"] : status.label
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }
}
