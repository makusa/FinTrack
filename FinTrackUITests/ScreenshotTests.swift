//
//  ScreenshotTests.swift
//  FinTrackUITests
//
//  Screenshot harness for presentation / App Store captures.
//  Launches the app in -FTDemoMode (in-memory store + demo dataset, lock and
//  coach marks bypassed, Placement tier simulated), walks the main screens and
//  attaches a PNG for each. Extract them with:
//
//    xcrun xcresulttool export attachments --path <result>.xcresult \
//                                          --output-path <dir>
//
//  Navigation notes (learned the hard way):
//   • Rows are not exposed as `cells` — the screens use custom SwiftUI layouts.
//     Target them by label prefix instead.
//   • Never tap navigationBars.buttons[0] to go back: on a root screen that is
//     the "+" button, which opens a modal that blocks every later capture.
//     Re-tapping the current tab pops to root, which is safe everywhere.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private var shotIndex = 0

    override func setUpWithError() throws {
        // Keep going after a soft failure so one missing screen never costs us
        // the whole capture run.
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments = [
            "-FTDemoMode",
            "-appLanguage", "fr",
            "-fintrack.dev.tierOverride", "placement",
            "-AppleLanguages", "(fr-CA)",
            "-AppleLocale", "fr_CA",
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

    // MARK: - Capture run

    func testCaptureAllScreens() throws {
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
        if tapTab("Comptes") {
            capture("comptes")
            if tapRow(startingWith: "Compte chèques") {
                capture("compte-detail")
            } else {
                XCTFail("Détail de compte : ligne « Compte chèques » introuvable.")
            }
            tapTab("Comptes")   // pop to root
        }

        // ── 3. Transactions ──────────────────────────────────────────────
        if tapTab("Transactions") {
            capture("transactions")
            app.swipeUp(); settle(1.2)
            capture("transactions-suite")
        }

        // ── 4. Gérer + sous-écrans ───────────────────────────────────────
        // (libellé de la ligne, nom de fichier, ligne de détail à ouvrir)
        let sections: [(row: String, slug: String, detail: String?)] = [
            ("Budgets",             "budgets",             "Alimentation"),
            ("Projets d'épargne",   "projets-epargne",     "Voyage au Japon"),
            ("Récurrences",         "recurrences",         nil),
            ("Prêts",               "prets",               "Hypothèque"),
            ("Marges de crédit",    "marges-de-credit",    "Marge de crédit"),
            ("Comptes enregistrés", "comptes-enregistres", nil),
        ]

        for section in sections {
            guard tapTab("Gérer") else { break }
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
        if tapTab("Gérer") {
            tapTab("Gérer")     // pop to root
            capture("gerer")
        }
        if tapTab("Réglages") {
            capture("reglages")
        }
    }
}
