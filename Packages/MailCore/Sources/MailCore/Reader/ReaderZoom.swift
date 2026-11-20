/// How large the reader shows a message: one of a few steps, as a browser's page zoom has. The reader keeps it on
/// the device it was chosen on (ADR-024).
public struct ReaderZoom: Equatable, Sendable {
    public static let steps: [Double] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private static let standardStep = 4

    public static let standard = ReaderZoom(step: standardStep)

    private let step: Int

    private init(step: Int) { self.step = step }

    /// The step nearest to a stored factor, or the standard size for a value that is no size.
    public init(stored: Double?) {
        guard let stored, stored.isFinite, stored > 0 else {
            self = .standard
            return
        }
        let nearest = Self.steps.indices.min { abs(Self.steps[$0] - stored) < abs(Self.steps[$1] - stored) }
        self.init(step: nearest ?? Self.standardStep)
    }

    /// What to multiply a message's size by.
    public var factor: Double { Self.steps[step] }
    public var isStandard: Bool { step == Self.standardStep }
    public var canZoomIn: Bool { step < Self.steps.count - 1 }
    public var canZoomOut: Bool { step > 0 }

    public func zoomedIn() -> ReaderZoom { canZoomIn ? ReaderZoom(step: step + 1) : self }
    public func zoomedOut() -> ReaderZoom { canZoomOut ? ReaderZoom(step: step - 1) : self }
}
