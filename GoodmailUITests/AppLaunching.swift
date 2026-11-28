import XCTest

/// A language the app ships in, as the launch arguments that pick it.
enum AppLanguage {
    case english, hebrew

    var arguments: [String] {
        switch self {
        case .english: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        case .hebrew: ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"]
        }
    }
}

/// How fast the app's windows animate. `.fast` (`-GoodmailFastAnimations`, a Debug-only switch) suits a class that
/// only waits for animations to end. A class that checks an animation's frames, or times a gesture against one, keeps
/// `.realTime`.
enum AnimationSpeed {
    case realTime, fast

    var arguments: [String] {
        switch self {
        case .realTime: []
        case .fast: ["-GoodmailFastAnimations", "YES"]
        }
    }
}

extension XCUIApplication {
    /// Launches the app on the synthetic mailbox (`SyntheticMailbox`): `threads` conversations, seeded fresh, with
    /// nothing arriving during the test. Returns once the list shows its rows.
    @MainActor
    static func launchedOnSyntheticMail(
        threads: Int = 200, language: AppLanguage = .english, animations: AnimationSpeed,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-GoodmailSyntheticThreads", "\(threads)", "-GoodmailSyntheticArrivalEvery", "3600"]
            + language.arguments + animations.arguments
        app.launch()
        XCTAssertTrue(
            app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15), "the list shows its rows",
            file: file, line: line)
        return app
    }
}
