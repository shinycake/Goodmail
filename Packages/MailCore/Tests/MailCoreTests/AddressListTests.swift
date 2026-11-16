import Foundation
import Testing

@testable import MailCore

/// The commas that split an address list, wherever quotes and angle brackets fall.
struct AddressListTests {
    @Test(arguments: [
        ("a@x.com, b@x.com", ["a@x.com", "b@x.com"]),
        (#""Levi, Dana" <dana@x.com>, b@x.com"#, [#""Levi, Dana" <dana@x.com>"#, "b@x.com"]),
        ("Dana <dana,levi@x.com>, b@x.com", ["Dana <dana,levi@x.com>", "b@x.com"]),
        // A quote inside angle brackets hides a closing bracket from the scan, until it closes.
        (#"<"a>,b"@x.com>, c@x.com"#, [#"<"a>,b"@x.com>"#, "c@x.com"]),
        // Angle brackets inside quotes are text: the comma after the quote still splits.
        (#""<Dana" a@x.com, b@x.com"#, [#""<Dana" a@x.com"#, "b@x.com"]),
        ("a@x.com,", ["a@x.com", ""]),
        ("", [""]),
    ])
    func splitsOnlyAtCommasOutsideQuotesAndBrackets(list: String, entries: [String]) {
        var parts: [Substring] = []
        var start = list.startIndex
        for separator in Contact.separators(in: list) {
            parts.append(list[start..<separator])
            start = list.index(after: separator)
        }
        parts.append(list[start...])
        #expect(parts.map { $0.trimmingCharacters(in: .whitespaces) } == entries)
    }

    @Test func aListIsParsedIntoItsContacts() {
        #expect(
            Contact.list(parsing: #"<"a>,b"@x.com>, "Levi, Dana" <dana@x.com>,"#) == [
                Contact(name: nil, address: #""a>,b"@x.com"#),
                Contact(name: "Levi, Dana", address: "dana@x.com"),
            ])
    }
}
