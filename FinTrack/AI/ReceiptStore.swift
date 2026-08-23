//  ReceiptStore.swift — Local receipt image storage (paid AI, Phase 2)
//
//  Receipt images live on-device only (no CloudKit — consistent with local-first,
//  and images are heavy) under Documents/Receipts/, as compressed JPEGs named
//  "date_merchant_amount_xxxx.jpg" for readability. The file name is stored on the
//  Transaction; deleting the transaction should delete the file.
import Foundation
import UIKit

enum ReceiptStore {

    /// Documents/Receipts/, created on first access.
    static var folderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Receipts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Save a receipt image; returns the stored file name (nil on failure).
    static func save(_ image: UIImage, date: Date, merchant: String?, amount: Decimal) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let name = makeFileName(date: date, merchant: merchant, amount: amount)
        let url = folderURL.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return name }
        catch { return nil }
    }

    static func load(_ fileName: String) -> UIImage? {
        let url = folderURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func url(for fileName: String) -> URL {
        folderURL.appendingPathComponent(fileName)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(fileName))
    }

    // MARK: - Naming

    /// "2026-08-22_Metro_45-67_A1B2C3.jpg" — readable, with a short unique suffix
    /// so two similar receipts never collide.
    private static func makeFileName(date: Date, merchant: String?, amount: Decimal) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = df.string(from: date)
        let merchantStr = sanitize(merchant ?? "recu")
        let amountStr = "\(amount)".replacingOccurrences(of: ".", with: "-")
        let unique = String(UUID().uuidString.prefix(6))
        return "\(dateStr)_\(merchantStr)_\(amountStr)_\(unique).jpg"
    }

    /// Keep alphanumerics, replace the rest with "-", cap length.
    private static func sanitize(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            out.append(CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-")
        }
        let capped = String(out.prefix(30))
        return capped.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty
            ? "recu" : capped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
