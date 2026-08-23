//  ReceiptScanner.swift — On-device receipt OCR (paid AI, Phase 2)
//
//  Uses Vision (on-device, no network, no cost) to read a receipt image, then
//  heuristically extracts the total, date and merchant. Best-effort: results are
//  meant to PRE-FILL a transaction the user then reviews, never to auto-commit.
import Foundation
import Vision
import UIKit

enum ReceiptScanner {

    struct ScanResult {
        var total: Decimal?
        var date: Date?
        var merchant: String?
        var currency: String?
        var rawText: String
    }

    /// Read a receipt image and extract its likely total, date and merchant.
    static func scan(_ image: UIImage) async -> ScanResult {
        guard let cg = image.cgImage else { return ScanResult(rawText: "") }
        let lines = await recognizeText(cg)
        return parse(lines)
    }

    // MARK: - OCR

    private static func recognizeText(_ image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: []) }
        }
    }

    // MARK: - Parsing (heuristic)

    private static func parse(_ lines: [String]) -> ScanResult {
        var result = ScanResult(rawText: lines.joined(separator: "\n"))
        result.merchant = findMerchant(lines)
        result.total = findTotal(lines)
        result.date = findDate(lines)
        result.currency = findCurrency(lines)
        return result
    }

    /// Currency: prefer an explicit ISO code; accept unambiguous symbols. "$" alone
    /// is left nil (CAD vs USD is ambiguous) — the account currency then decides.
    private static func findCurrency(_ lines: [String]) -> String? {
        let text = lines.joined(separator: " ").uppercased()
        // Match codes as WHOLE WORDS — "EUR" must not fire inside "VALEUR",
        // "COULEUR", "HAUTEUR"… (many French words end in "-eur").
        for code in ["CAD", "USD", "EUR", "GBP", "JPY", "CHF", "AUD", "MXN"] {
            if text.range(of: "\\b\(code)\\b", options: .regularExpression) != nil {
                return code
            }
        }
        if text.contains("€") { return "EUR" }
        if text.contains("£") { return "GBP" }
        if text.contains("¥") { return "JPY" }
        return nil
    }

    /// Merchant: the first meaningful line (receipts put the store name on top),
    /// skipping lines that are just amounts or generic headers.
    private static func findMerchant(_ lines: [String]) -> String? {
        lines.first { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            let lower = t.lowercased()
            return t.count >= 3
                && amounts(in: t).isEmpty
                && !lower.contains("reçu") && !lower.contains("receipt")
                && !lower.contains("facture") && !lower.contains("invoice")
        }?.trimmingCharacters(in: .whitespaces)
    }

    /// Total: prefer the largest amount on a line mentioning "total" (excluding
    /// subtotals); otherwise fall back to the largest amount on the receipt.
    private static func findTotal(_ lines: [String]) -> Decimal? {
        var totalLine: [Decimal] = []
        var all: [Decimal] = []
        for line in lines {
            let lower = line.lowercased()
            let amts = amounts(in: line)
            all.append(contentsOf: amts)
            if lower.contains("total"), !lower.contains("sous"), !lower.contains("sub") {
                totalLine.append(contentsOf: amts)
            }
        }
        return totalLine.max() ?? all.max()
    }

    /// Amounts with two decimals ("12.34" or "12,34"), returned as Decimal.
    private static func amounts(in s: String) -> [Decimal] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+[.,]\d{2}"#) else { return [] }
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            Decimal(string: ns.substring(with: $0.range).replacingOccurrences(of: ",", with: "."))
        }
    }

    /// Date: use the system data detector; prefer a plausible (non-future) date.
    private static func findDate(_ lines: [String]) -> Date? {
        let text = lines.joined(separator: "\n")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let tomorrow = Date.now.addingTimeInterval(86_400)
        for m in matches { if let d = m.date, d <= tomorrow { return d } }
        return nil   // no plausible (non-future) date — better nil than a future one
    }
}
