//
//  PDFTextExtractor.swift
//  FinTrack
//
//  Pulls text out of a bank-statement PDF for PDFStatementParser. Two strategies:
//  (1) embedded text via PDFKit (digital statements — the common case); (2) if the
//  PDF carries little/no text (scanned), fall back to on-device OCR with Vision,
//  page-rasterized and read top-to-bottom. Impure (PDFKit/Vision/UIKit), so not
//  unit-tested — the pure line parsing lives in PDFStatementParser.
//

import Foundation
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#endif

enum PDFExtractError: Error, Equatable {
    case notPDF
    case noText
}

enum PDFTextExtractor {
    /// Below this many embedded characters we assume the PDF is scanned and OCR it.
    private static let minTextChars = 24

    static func extractText(from data: Data) throws -> String {
        guard let doc = PDFDocument(data: data) else { throw PDFExtractError.notPDF }

        // 1) Embedded text.
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { pages.append(s) }
        }
        let embedded = pages.joined(separator: "\n")
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count >= minTextChars {
            return embedded
        }

        // 2) Scanned → OCR.
        let ocr = try ocrText(from: doc)
        if !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ocr }
        if !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return embedded }
        throw PDFExtractError.noText
    }

    // MARK: OCR

    private static func ocrText(from doc: PDFDocument) throws -> String {
        var lines: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let cg = render(page: page) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US"]
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            // Vision's y axis is bottom-up: larger midY = higher on the page.
            let sorted = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            for o in sorted {
                if let top = o.topCandidates(1).first { lines.append(top.string) }
            }
        }
        return lines.joined(separator: "\n")
    }

    #if canImport(UIKit)
    private static func render(page: PDFPage) -> CGImage? {
        let rect = page.bounds(for: .mediaBox)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scale: CGFloat = 2
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cg)
        }
        return image.cgImage
    }
    #else
    private static func render(page: PDFPage) -> CGImage? { nil }
    #endif
}
