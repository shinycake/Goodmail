import Foundation

/// The best score, kept on this device only: a game played in a spare moment, not a setting to follow the reader.
enum PlaneGameBest {
    static let key = "planeGameBest"

    /// Records a game that ended on `score`, keeping it if it beats the best so far.
    static func record(_ score: Int, in defaults: UserDefaults) -> PlaneGameResult {
        let best = defaults.integer(forKey: key)
        guard score > best else { return PlaneGameResult(score: score, best: best, isNewBest: false) }
        defaults.set(score, forKey: key)
        return PlaneGameResult(score: score, best: score, isNewBest: true)
    }
}
