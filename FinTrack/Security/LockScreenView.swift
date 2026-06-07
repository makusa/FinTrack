//
//  LockScreenView.swift
//  FinTrack
//

import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(AppLockManager.self) private var lockManager

    @State private var pin: String = ""
    @State private var isError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon + greeting
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)

                    VStack(spacing: 4) {
                        Text("FinTrack")
                            .font(.largeTitle.weight(.bold))
                        if !lockManager.userName.isEmpty {
                            Text(lang.f("lock.greeting", lockManager.userName))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer().frame(height: 48)

                // PIN pad
                if lockManager.isBlocked {
                    blockedView
                } else {
                    VStack(spacing: 16) {
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .transition(.opacity)
                        }

                        PINPadView(pin: $pin, length: 4, isError: isError) { entered in
                            handlePINEntry(entered)
                        }
                    }
                }

                Spacer().frame(height: 32)

                // FaceID / TouchID button
                if lockManager.useBiometrics && lockManager.biometricType != .none && !lockManager.isBlocked {
                    Button {
                        triggerBiometrics()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: lockManager.biometricType.systemImage)
                                .font(.title2)
                            Text(lang.f("lock.biometric.use", lockManager.biometricType.label))
                                .font(.callout)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            if lockManager.useBiometrics {
                triggerBiometrics()
            }
        }
    }

    // MARK: - Blocked view

    private var blockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text(lang["lock.blocked"])
                .font(.headline)
                .foregroundStyle(.red)
            if let until = lockManager.blockUntil {
                Text(lang["lock.blocked.wait"])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: until, by: 1)) { _ in
                    let remaining = max(0, until.timeIntervalSinceNow)
                    Text(String(format: "%0.0f s", remaining))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(28)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Logic

    @MainActor
    private func handlePINEntry(_ entered: String) {
        let success = lockManager.unlockWithPIN(entered)
        if success {
            isError = false
            errorMessage = ""
        } else {
            isError = true
            let remaining = 5 - lockManager.failedAttempts
            if remaining > 0 {
                errorMessage = lang.f("lock.pin.wrong", remaining)
            }
            // Shake + reset after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pin = ""
                isError = false
                errorMessage = remaining > 0 ? errorMessage : ""
            }
        }
    }

    private func triggerBiometrics() {
        Task {
            let _ = await lockManager.unlockWithBiometrics()
        }
    }
}
