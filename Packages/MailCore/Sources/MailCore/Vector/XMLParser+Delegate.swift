#if canImport(FoundationXML)
    import Foundation
    public import FoundationXML  // XMLParser on Linux
#else
    public import Foundation
#endif

extension XMLParser {
    /// Parses the document, calling `delegate` as it goes, and then lets go of `delegate`.
    ///
    /// The one place that sets a parser's delegate. Apple's `XMLParser` doesn't retain it (`unowned(unsafe)`), so
    /// setting it is unsafe there. Safe: `delegate` is this function's argument, alive through the synchronous
    /// parse, and cleared before the function returns. Linux's `XMLParser` holds it weakly, which is safe as it is.
    public func parse(with delegate: some XMLParserDelegate) -> Bool {
        #if canImport(FoundationXML)
            self.delegate = delegate
            defer { self.delegate = nil }
        #else
            unsafe self.delegate = delegate
            defer { unsafe self.delegate = nil }
        #endif
        return withExtendedLifetime(delegate) { parse() }
    }
}
