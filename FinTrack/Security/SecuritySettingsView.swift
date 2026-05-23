//
//  SecuritySettingsView.swift
//  FinTrack
//

import SwiftUI
import LocalAuthentication

struct SecuritySettingsView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var lockManager = AppLockManager.shared

    @State private var showChangePIN     = false
    @State private var showChangeName    = false
    @State private var confirmReset      = false
    @State private var newName: String   = ""

    var body: some View {
        List {
            // MARK: Account
            Section(lang["security.account"]) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Text(initials)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lockManager.userName)
                            .font(.body.weight(.medium))
                        Text(lang["security.account.local"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(lang["action.edit"]) { showChangeName = true }
                        .font(.callout)
                }
                .padding(.vertical, 4)
            }

            // MARK: PIN
            Section(lang["security.pin"]) {
                Button {
                    showChangePIN = true
                } label: {
                    Label(lang["security.pin.change"], systemImage: "lock.rotation")
                        .foregroundStyle(.primary)
                }
            }

            // MARK: Biometrics
            if lockManager.biometricType != .none {
                Section(lockManager.biometricType.label) {
                    Toggle(
                        lang.f("security.biometric.toggle", lockManager.biometricType.label),
                        isOn: Binding(
                            get:  { lockManager.useBiometrics },
                            set:  { lockManager.updateBiometrics($0) }
                        )
                    )
                }
            }

            // MARK: Auto-lock
            Section(lang["security.autolock"]) {
                Picker(lang["security.autolock.delay"], selection: Binding(
                    get: { lockManager.autoLockDelay },
                    set: { lockManager.updateAutoLockDelay($0) }
                )) {
                    ForEach(AutoLockDelay.allCases) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text(lang["security.autolock.footer"])
                    .font(.caption)
            }

            // MARK: Lock now
            Section {
                Button {
                    lockManager.lock()
                } label: {
                    Label(lang["security.lock.now"], systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                }
            }

            // MARK: Reset
            Section {
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label(lang["security.reset"], systemImage: "person.badge.minus")
                }
            } footer: {
                Text(lang["security.reset.footer"])
            }
        }
        .navigationTitle(lang["security.title"])
        .navigationBarTitleDisplayMode(.inline)

        // MARK: Change PIN sheet
        .sheet(isPresented: $showChangePIN) {
            ChangePINView()
        }

        // MARK: Change name alert
        .alert(lang["security.account.name.change"], isPresented: $showChangeName) {
            TextField(lang["setup.name.placeholder"], text: $newName)
                .autocorrectionDisabled()
            Button(lang["action.save"]) {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 2 { lockManager.updateUserName(trimmed) }
                newName = ""
            }
            Button(lang["action.cancel"], role: .cancel) { newName = "" }
        } message: {
            Text(lang["security.account.name.change.msg"])
        }

        // MARK: Confirm reset
        .confirmationDialog(lang["security.reset"], isPresented: $confirmReset, titleVisibility: .visible) {
            Button(lang["security.reset"], role: .destructive) {
                lockManager.resetAccount()
            }
            Button(lang["action.cancel"], role: .cancel) {}
        } message: {
            Text(lang["security.reset.confirm"])
        }
    }

    private var initials: String {
        lockManager.userName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}

// MARK: - Change PIN flow

struct ChangePINView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @State private var lockManager = AppLockManager.shared

    @State private var step: Step = .current
    @State private var currentPIN: String = ""
    @State private var newPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var isError = false
    @State private var errorMsg = ""

    enum Step { case current, newPIN, confirm, done }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                switch step {
                case .current:
                    pinStep(
                        title: lang["security.pin.enter.current"],
                        subtitle: lang["security.pin.enter.current.sub"],
                        pin: $currentPIN,
                        onComplete: verifyCurrent
                    )
                case .newPIN:
                    pinStep(
                        title: lang["security.pin.enter.new"],
                        subtitle: lang["security.pin.enter.new.sub"],
                        pin: $newPIN,
                        onComplete: { _ in withAnimation { step = .confirm } }
                    )
                case .confirm:
                    pinStep(
                        title: lang["setup.pin.confirm.title"],
                        subtitle: lang["setup.pin.confirm.subtitle"],
                        pin: $confirmPIN,
                        onComplete: confirmNew
                    )
                case .done:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.green)
                        Text(lang["security.pin.changed"])
                            .font(.title2.weight(.bold))
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                    }
                }

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                Spacer()
            }
            .navigationTitle(lang["security.pin.change"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
            }
        }
    }

    private func pinStep(title: String, subtitle: String, pin: Binding<String>, onComplete: @escaping (String) -> Void) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.rotation")
                .font(.system(size: 40))
                .foregroundStyle(.accentColor)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.bold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            PINPadView(pin: pin, length: 4, isError: isError, onComplete: onComplete)
        }
    }

    private func verifyCurrent(_ entered: String) {
        let ok = lockManager.unlockWithPIN(entered)
        if ok {
            // Re-lock immediately so the state is clean
            lockManager.lock()
            isError = false
            errorMsg = ""
            withAnimation { step = .newPIN }
        } else {
            isError = true
            errorMsg = lang["security.pin.wrong.current"]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                currentPIN = ""
                isError = false
            }
        }
    }

    private func confirmNew(_ entered: String) {
        if entered == newPIN {
            lockManager.updatePIN(newPIN: newPIN)
            withAnimation { step = .done }
        } else {
            isError = true
            errorMsg = lang["setup.pin.mismatch"]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                confirmPIN = ""
                isError = false
                errorMsg = ""
            }
        }
    }
}
