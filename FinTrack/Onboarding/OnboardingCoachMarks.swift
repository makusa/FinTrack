//  OnboardingCoachMarks.swift — Reusable per-screen coach-mark onboarding.
//
//  • OnboardingManager: remembers which tours a user has seen (persisted on the
//    device, not synced — each device shows the guide once). Resettable for tests
//    or a "replay guides" setting.
//  • coachAnchor(_:): tags a view as a highlight target with a stable id.
//  • coachMarks(tour:steps:replay:): attaches a tour to a screen; auto-plays on
//    first visit, dims the screen, cuts a hole over the current target, shows a
//    bubble, and advances step by step.
import SwiftUI

// MARK: - Manager

@Observable
final class OnboardingManager {
    static let shared = OnboardingManager()
    private let key = "onboarding.seenTours"
    private var seen: Set<String>

    private init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    /// Bumped by resetAll so tours already on screen replay immediately.
    var replayToken = 0

    func hasSeen(_ tour: String) -> Bool { seen.contains(tour) }

    func markSeen(_ tour: String) {
        guard !seen.contains(tour) else { return }
        seen.insert(tour)
        persist()
    }

    /// Replay every guide (Settings → "Replay guides", or for testing).
    func resetAll() {
        seen.removeAll()
        persist()
        replayToken += 1
    }

    private func persist() {
        UserDefaults.standard.set(Array(seen), forKey: key)
    }
}

// MARK: - Step + anchor plumbing

struct CoachStep: Identifiable {
    let id = UUID()
    let anchor: String     // must match a coachAnchor(_:) id on the screen
    let title: String
    let message: String
}

struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Tag this view as a coach-mark target.
    func coachAnchor(_ id: String) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Attach a coach-mark tour. Auto-plays on first visit; set `replay` to true
    /// to play it again on demand.
    func coachMarks(tour: String, steps: [CoachStep], replay: Binding<Bool>? = nil) -> some View {
        modifier(CoachMarksModifier(tour: tour, steps: steps, replay: replay))
    }

    fileprivate func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .center) { mask().blendMode(.destinationOut) }
        }
    }
}

// MARK: - Overlay modifier

struct CoachMarksModifier: ViewModifier {
    let tour: String
    let steps: [CoachStep]
    var replay: Binding<Bool>?

    @State private var manager = OnboardingManager.shared
    @State private var active = false
    @State private var index = 0

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if active, index < steps.count {
                        if let anchor = anchors[steps[index].anchor] {
                            overlay(step: steps[index], rect: proxy[anchor], screen: proxy.size)
                        } else {
                            // Target not on screen (disabled widget, toolbar…) → skip it.
                            Color.clear.allowsHitTesting(false).onAppear { advance() }
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .task {
                // First visit → auto-play, after a beat so anchors are laid out.
                if !manager.hasSeen(tour) {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    if !manager.hasSeen(tour) { start() }
                }
            }
            .onChange(of: replay?.wrappedValue ?? false) { _, wants in
                if wants {
                    start()
                    replay?.wrappedValue = false
                }
            }
            .onChange(of: manager.replayToken) { _, _ in
                // Settings → "Replay guides": re-play on-screen tours right away.
                if !manager.hasSeen(tour) { start() }
            }
    }

    private func start() { index = 0; withAnimation(.easeInOut) { active = true } }

    private func advance() {
        if index + 1 < steps.count {
            withAnimation(.easeInOut) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        withAnimation(.easeInOut) { active = false }
        manager.markSeen(tour)
    }

    private func overlay(step: CoachStep, rect: CGRect, screen: CGSize) -> some View {
        let pad: CGFloat = 8
        let spot = rect.insetBy(dx: -pad, dy: -pad)
        let bubbleBelow = rect.midY < screen.height / 2
        return ZStack {
            // Dimmed backdrop with a hole punched over the target.
            Color.black.opacity(0.72)
                .reverseMask {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .frame(width: spot.width, height: spot.height)
                        .position(x: spot.midX, y: spot.midY)
                }
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            // Highlight ring around the target.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: spot.width, height: spot.height)
                .position(x: spot.midX, y: spot.midY)
                .allowsHitTesting(false)

            // Explanation bubble, above or below the spotlight.
            VStack {
                if bubbleBelow {
                    Color.clear.frame(height: spot.maxY + 20)
                    bubble(step: step)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    bubble(step: step)
                    Color.clear.frame(height: screen.height - spot.minY + 20)
                }
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func bubble(step: CoachStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.headline).foregroundStyle(.white)
            Text(step.message)
                .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(index + 1) / \(steps.count)")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button(LanguageManager.shared["coach.skip"]) { finish() }
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                Button(index + 1 < steps.count ? LanguageManager.shared["coach.next"]
                                               : LanguageManager.shared["coach.done"]) { advance() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.leading, 8)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: 340)
        .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 12, y: 4)
    }
}
