//
//  SetupAccountView.swift
//  FinTrack
//
//  Shown on first launch when no account is configured.
//  Guides the user through: name → PIN creation → biometrics.
//

import SwiftUI
import LocalAuthentication

struct SetupAccountView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var lockManager = AppLockManager.shared

    // Step management
    @State private var step: Step = .name

    // Fields
    @State private var userName: String = ""
    @State private var pin: String = ""
    @State private var pinConfirm: String = ""
    @State private var useBiometrics: Bool = false
    @State private var autoLock: AutoLockDelay = .immediately
    @State private var pinMismatch: Bool = false

    enum Step { case name, pin, confirm, biometrics, autoLock, done }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: stepProgress)
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 32) {
                        stepView
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 40)
                }

                // Bottom CTA
                VStack(spacing: 12) {
                    Button(action: advance) {
                        Text(ctaLabel)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canAdvance ? Color.accentColor : Color(.systemGray4),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(!canAdvance)

                    if step == .biometrics || step == .autoLock {
                        Button(lang["action.skip"]) { advance() }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
            .navigationTitle(lang["setup.title"])
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Step views

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .name:       nameStep
        case .pin:        pinStep(isConfirm: false)
        case .confirm:    pinStep(isConfirm: true)
        case .biometrics: biometricsStep
        case .autoLock:   autoLockStep
        case .done:       Color.clear
        }
    }

    // MARK: Name

    private var nameStep: some View {
        VStack(spacing: 24) {
            stepIcon("person.circle.fill", color: .accentColor)
            VStack(spacing: 8) {
                Text(lang["setup.name.title"])
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(lang["setup.name.subtitle"])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField(lang["setup.name.placeholder"], text: $userName)
                .textContentType(.name)
                .autocorrectionDisabled()
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: PIN

    private func pinStep(isConfirm: Bool) -> some View {
        VStack(spacing: 24) {
            stepIcon("lock.fill", color: .orange)
            VStack(spacing: 8) {
                Text(isConfirm ? lang["setup.pin.confirm.title"] : lang["setup.pin.title"])
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(isConfirm ? lang["setup.pin.confirm.subtitle"] : lang["setup.pin.subtitle"])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if isConfirm && pinMismatch {
                    Text(lang["setup.pin.mismatch"])
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            PINPadView(
                pin: isConfirm ? $pinConfirm : $pin,
                length: 4,
                onComplete: { _ in advance() }
            )
        }
    }

    // MARK: Biometrics

    private var biometricsStep: some View {
        let type = lockManager.biometricType
        return VStack(spacing: 24) {
            stepIcon(type.systemImage, color: .green)
            VStack(spacing: 8) {
                Text(lang.f("setup.biometric.title", type.label))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(lang.f("setup.biometric.subtitle", type.label))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Toggle(lang.f("setup.biometric.toggle", type.label), isOn: $useBiometrics)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Auto-lock

    private var autoLockStep: some View {
        VStack(spacing: 24) {
            stepIcon("timer", color: .purple)
            VStack(spacing: 8) {
                Text(lang["setup.autolock.title"])
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(lang["setup.autolock.subtitle"])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 0) {
                ForEach(Array(AutoLockDelay.allCases.enumerated()), id: \.element) { index, delay in
                    Button {
                        autoLock = delay
                    } label: {
                        HStack {
                            Text(delay.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if autoLock == delay {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    if index < AutoLockDelay.allCases.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Navigation

    private var stepProgress: Double {
        switch step {
        case .name:       return 0.2
        case .pin:        return 0.4
        case .confirm:    return 0.6
        case .biometrics: return 0.8
        case .autoLock:   return 0.95
        case .done:       return 1.0
        }
    }

    private var ctaLabel: String {
        switch step {
        case .name:       return lang["action.next"]
        case .pin:        return pin.count == 4 ? lang["action.next"] : lang["setup.pin.enter4"]
        case .confirm:    return lang["action.confirm"]
        case .biometrics: return lang["action.next"]
        case .autoLock:   return lang["setup.finish"]
        case .done:       return lang["setup.finish"]
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .name:       return userName.trimmingCharacters(in: .whitespaces).count >= 2
        case .pin:        return pin.count == 4
        case .confirm:    return pinConfirm.count == 4
        case .biometrics, .autoLock, .done: return true
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch step {
            case .name:
                step = .pin

            case .pin:
                if pin.count == 4 { step = .confirm }

            case .confirm:
                if pinConfirm == pin {
                    pinMismatch = false
                    step = lockManager.biometricType != .none ? .biometrics : .autoLock
                } else {
                    pinMismatch = true
                    pinConfirm  = ""
                }

            case .biometrics:
                step = .autoLock

            case .autoLock:
                finishSetup()

            case .done:
                break
            }
        }
    }

    private func finishSetup() {
        lockManager.setup(
            userName: userName.trimmingCharacters(in: .whitespaces),
            pin: pin,
            useBiometrics: useBiometrics,
            autoLockDelay: autoLock
        )
        step = .done
    }

    // MARK: - Sub-views

    private func stepIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 52))
            .foregroundStyle(color)
            .frame(width: 80, height: 80)
            .background(color.opacity(0.12), in: Circle())
    }
}

// MARK: - Next label helper

extension LanguageManager {
    fileprivate var next: String { self["action.next"] }
}
