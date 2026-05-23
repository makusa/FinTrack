//
//  PINPadView.swift
//  FinTrack
//
//  Reusable PIN entry keypad. Shows dot indicators and a numeric grid.
//  onComplete is called when `length` digits have been entered.
//

import SwiftUI

struct PINPadView: View {
    @Binding var pin: String
    var length: Int = 4
    var isError: Bool = false
    var onComplete: ((String) -> Void)? = nil

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    var body: some View {
        VStack(spacing: 24) {
            // Dot indicators
            HStack(spacing: 18) {
                ForEach(0..<length, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count
                              ? (isError ? Color.red : Color.accentColor)
                              : Color(.systemGray4))
                        .frame(width: 14, height: 14)
                        .animation(.easeInOut(duration: 0.15), value: pin.count)
                        .modifier(ShakeModifier(trigger: isError && i == 0))
                }
            }

            // Key grid
            VStack(spacing: 12) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row, id: \.self) { key in
                            if key.isEmpty {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 76, height: 76)
                            } else {
                                PINKeyButton(label: key) {
                                    handleKey(key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
        } else if pin.count < length {
            pin += key
            if pin.count == length {
                onComplete?(pin)
            }
        }
    }
}

// MARK: - Key button

private struct PINKeyButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 76, height: 76)
                Text(label)
                    .font(.title.weight(.regular))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shake animation modifier

struct ShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, newVal in
                guard newVal else { return }
                withAnimation(.linear(duration: 0.05).repeatCount(6, autoreverses: true)) {
                    offset = 6
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    offset = 0
                }
            }
    }
}
