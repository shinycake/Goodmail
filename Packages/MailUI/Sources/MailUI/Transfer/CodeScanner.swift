import SwiftUI

// VisionKit's data scanner doesn't exist on Mac Catalyst, so the Mac build has a scanner that is never available,
// and the receive screen shows its existing "can't scan" state.
#if targetEnvironment(macCatalyst)

    /// A stand-in for the camera scanner, which the Mac doesn't have.
    struct CodeScanner: View {
        let accepts: (String) -> Bool
        let found: (String) -> Void

        static var isAvailable: Bool { false }

        var body: some View { EmptyView() }
    }

#else

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
                recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                isHighlightingEnabled: true)
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
                _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                allItems: [RecognizedItem]
            ) {
                for case .barcode(let code) in addedItems {
                    guard !reported, let text = code.payloadStringValue, scanner.accepts(text) else { continue }
                    reported = true
                    scanner.found(text)
                }
            }
        }
    }

#endif
