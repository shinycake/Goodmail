import SwiftUI
import Vision
import VisionKit

/// The camera, looking for a QR code that `accepts` says is the one; it reports the first such code once.
struct CodeScanner: UIViewControllerRepresentable {
    let accepts: (String) -> Bool
    let found: (String) -> Void

    /// Whether this device has a camera that can scan, which a simulator doesn't.
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.scanner = self
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanner: self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var scanner: CodeScanner
        private var reported = false

        init(scanner: CodeScanner) {
            self.scanner = scanner
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            for case .barcode(let code) in addedItems {
                guard !reported, let text = code.payloadStringValue, scanner.accepts(text) else { continue }
                reported = true
                scanner.found(text)
            }
        }
    }
}
