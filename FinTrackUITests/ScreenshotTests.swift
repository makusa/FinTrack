//
//  ScreenshotTests.swift
//  FinTrackUITests
//
//  Screenshot harness for presentation / App Store / landing-page captures.
//  Launches the app in -FTDemoMode (in-memory store + demo dataset, lock and
//  coach marks bypassed, Placement tier simulated), walks the main screens and
//  attaches a PNG for each.
//
//  Two runs, one per language. The slugs are identical in both so the two sets
//  map one to one:
//
//    xcodebuild test -scheme FinTrack \
//      -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
//      -only-testing:FinTrackUITests/ScreenshotTests/testCaptureAllScreensEN \
//      -resultBundlePath /tmp/shots-en.xcresult
//
//    xcrun xcresulttool export attachments --path /tmp/shots-en.xcresult \
//                                          --output-path /tmp/shots-en
//
//  Navigation notes (learned the hard way):
//   • Rows are not exposed as `cells` — the screens use custom SwiftUI layouts.
//     Target them by label prefix instead.
//   • Never tap navigationBars.buttons[0] to go back: on a root screen that is
//     the "+" button, which opens a modal that blocks every later capture.
//     Re-tapping the current tab pops to root, which is safe everywhere.
//   • Demo content (account names, budget names…) is seeded in the language the
//     app launched in, so every row prefix below has to be language-aware too.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private var shotIndex = 0
    private var isEN = false

    override func setUpWithError() throws {
        // Keep going after a soft failure so one missing screen never costs us
        // the whole capture run.
        continueAfterFailure = true
    }

    // MARK: - Language

    /// Picks the French or English variant of a label the harness has to match.
    private func L(_ fr: String, _ en: String) -> String { isEN ? en : fr }

    private func launch(english: Bool) {
        isEN = english
        shotIndex = 0
        app = XCUIApplication()
        app.launchArguments = [
            "-FTDemoMode",
            "-appLanguage", english ? "en" : "fr",
            "-fintrack.dev.tierOverride", "placement",
            "-AppleLanguages", english ? "(en-CA)" : "(fr-CA)",
            "-AppleLocale", english ? "en_CA" : "fr_CA",
        ]
        app.launch()
    }

    // MARK: - Helpers

    private func capture(_ name: String) {
        shotIndex += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%02d-%@", shotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Closes any modal left open, so it never covers a later capture.
    private func dismissAnySheet() {
        for label in ["Annuler", "Cancel", "Fermer", "Terminé", "Done"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                settle(1.0)
                return
            }
        }
    }

    /// Selects a tab. Re-tapping the current tab also pops its stack to root,
    /// which is how every screen returns from a pushed detail view.
    @discardableResult
    private func tapTab(_ label: String) -> Bool {
        dismissAnySheet()
        let tab = app.tabBars.buttons[label]
        guard tab.waitForExistence(timeout: 15) else {
            XCTFail("Onglet introuvable : \(label)")
            return false
        }
        tab.tap()
        settle(2)
        return true
    }

    /// Rows carry compound accessibility labels ("Compte chèques, Banque
    /// Nationale · Compte courant, 7 770,30 $ CA"), so match on the prefix.
    private func row(startingWith prefix: String) -> XCUIElement? {
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", prefix)
        for collection in [app.buttons, app.cells, app.staticTexts] {
            let match = collection.matching(predicate).firstMatch
            if match.exists { return match }
        }
        return nil
    }

    @discardableResult
    private func tapRow(startingWith prefix: String) -> Bool {
        for attempt in 0..<3 {
            if let element = row(startingWith: prefix) {
                if element.isHittable {
                    element.tap()
                    settle(2)
                    return true
                }
            }
            // Not on screen yet (or below the fold) — scroll and retry.
            if attempt < 2 {
                app.swipeUp()
                settle(1.0)
            }
        }
        return false
    }

    // MARK: - Tests

    func testCaptureAllScreensFR() throws {
        launch(english: false)
        try runCapture()
    }

    func testCaptureAllScreensEN() throws {
        launch(english: true)
        try runCapture()
    }

    // MARK: - Capture run

    private func runCapture() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30),
                      "L'application n'a pas atteint l'écran principal.")
        settle(3)

        // ── 1. Tableau de bord ───────────────────────────────────────────
        capture("tableau-de-bord")
        app.swipeUp(); settle(1.2)
        capture("tableau-de-bord-suite")
        app.swipeUp(); settle(1.2)
        capture("tableau-de-bord-analyses")

        // ── 2. Comptes ───────────────────────────────────────────────────
        if tapTab(L("Comptes", "Accounts")) {
            capture("comptes")
            if tapRow(startingWith: L("Compte chèques", "Chequing")) {
                capture("compte-detail")
            } else {
                XCTFail("Détail de compte : ligne introuvable.")
            }
            tapTab(L("Comptes", "Accounts"))   // pop to root
        }

        // ── 3. Transactions ──────────────────────────────────────────────
        if tapTab(L("Transactions", "Transactions")) {
            capture("transactions")
            app.swipeUp(); settle(1.2)
            capture("transactions-suite")
        }

        // ── 4. Gérer + sous-écrans ───────────────────────────────────────
        // (libellé de la ligne, nom de fichier, ligne de détail à ouvrir)
        let sections: [(row: String, slug: String, detail: String?)] = [
            (L("Budgets", "Budgets"),                      "budgets",             L("Alimentation", "Groceries")),
            (L("Projets d'épargne", "Savings Goals"),      "projets-epargne",     L("Voyage au Japon", "Trip to Japan")),
            (L("Récurrences", "Recurring"),                "recurrences",         nil),
            (L("Prêts", "Loans"),                          "prets",               L("Hypothèque", "Mortgage")),
            (L("Marges de crédit", "Credit Lines"),        "marges-de-credit",    L("Marge de crédit", "Personal line")),
            (L("Comptes enregistrés", "Registered Accounts"), "comptes-enregistres", nil),
        ]

        for section in sections {
            guard tapTab(L("Gérer", "Manage")) else { break }
            guard tapRow(startingWith: section.row) else {
                XCTFail("Ligne introuvable dans Gérer : \(section.row)")
                continue
            }
            capture(section.slug)

            if let detail = section.detail, tapRow(startingWith: detail) {
                capture("\(section.slug)-detail")
            }
        }

        // ── 5. Gérer (racine) + Réglages ─────────────────────────────────
        if tapTab(L("Gérer", "Manage")) {
            tapTab(L("Gérer", "Manage"))     // pop to root
            capture("gerer")
        }
        if tapTab(L("Réglages", "Settings")) {
            capture("reglages")
        }
    }
}
