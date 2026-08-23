//  ScanReceiptView.swift — Receipt scan UI (paid AI, Phase 2)
//
//  Phase A (this file): pick an image → OCR → show detected total/date/merchant.
//  Phase B (next): "Create transaction" pre-fills the editor + stores the image.
import SwiftUI
import PhotosUI
import VisionKit

struct ScanReceiptView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: ReceiptScanner.ScanResult?
    @State private var scanning = false
    @State private var showCamera = false
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showCamera = true
                    } label: {
                        Label(lang["scan.camera"], systemImage: "camera")
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(lang["scan.pick"], systemImage: "photo.on.rectangle")
                    }
                } footer: {
                    Text(lang["scan.hint"])
                }

                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                    }
                }

                if scanning {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }

                if let result {
                    let amountStr = result.total.map { formatAmount($0) } ?? "—"
                    let dateStr = result.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
                    let merchantStr = result.merchant ?? "—"
                    Section {
                        detectRow(lang["scan.amount"], amountStr)
                        detectRow(lang["scan.date"], dateStr)
                        detectRow(lang["scan.merchant"], merchantStr)
                    } header: {
                        Text(lang["scan.detected"])
                    } footer: {
                        Text(lang["scan.review"])
                    }
                    Section {
                        Button {
                            showEditor = true
                        } label: {
                            Label(lang["scan.create"], systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle(lang["scan.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, _ in loadAndScan() }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentScannerView { img in
                    Task { @MainActor in
                        showCamera = false
                        if let img { process(img) }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showEditor, onDismiss: { dismiss() }) {
                NavigationStack {
                    AddEditTransactionView(mode: .create, prefill: makePrefill())
                }
            }
        }
    }

    private func makePrefill() -> TransactionPrefill {
        TransactionPrefill(
            amount: result?.total,
            date: result?.date,
            payee: result?.merchant,
            currencyCode: result?.currency,
            receiptImage: image
        )
    }

    private func loadAndScan() {
        guard let pickerItem else { return }
        Task { @MainActor in
            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { return }
            process(img)
        }
    }

    @MainActor
    private func process(_ img: UIImage) {
        image = img
        result = nil
        scanning = true
        Task {
            let r = await ReceiptScanner.scan(img)
            await MainActor.run { result = r; scanning = false }
        }
    }

    private func detectRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func formatAmount(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: d as NSDecimalNumber) ?? "\(d)"
    }
}

// MARK: - Document scanner (VisionKit)

/// Apple's document scanner: automatic edge detection, perspective correction and
/// image enhancement — far better than a raw photo for receipt OCR. Returns the
/// first scanned page (or nil on cancel/error).
struct DocumentScannerView: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: (UIImage?) -> Void
        init(onComplete: @escaping (UIImage?) -> Void) { self.onComplete = onComplete }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onComplete(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onComplete(nil)
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onComplete(nil)
        }
    }
}
