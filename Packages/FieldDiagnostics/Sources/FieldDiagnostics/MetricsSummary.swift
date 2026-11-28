/// What MetricKit measured of the app over a day, in plain numbers: how long it took to launch and come back, how
/// often it hung, the most memory it took, what it wrote to disk, and why it was ended.
public struct MetricsSummary: Sendable, Codable, Hashable {
    /// From the tap to the first frame of a launch.
    public let launches: DurationHistogram
    /// From the tap to the first frame of coming back from the background.
    public let resumes: DurationHistogram
    /// How long the main thread didn't answer, each time it hung.
    public let hangs: DurationHistogram
    /// The most memory the app took, in bytes. The Mac doesn't measure it.
    public let peakMemory: Int64?
    /// What the app wrote to disk, in bytes.
    public let diskWrites: Int64?
    /// Why the system ended the app, for each reason it did.
    public let exits: [ExitTally]

    public init(
        launches: DurationHistogram, resumes: DurationHistogram, hangs: DurationHistogram, peakMemory: Int64?,
        diskWrites: Int64?, exits: [ExitTally]
    ) {
        self.launches = launches
        self.resumes = resumes
        self.hangs = hangs
        self.peakMemory = peakMemory
        self.diskWrites = diskWrites
        self.exits = exits
    }
}
