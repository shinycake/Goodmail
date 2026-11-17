/// The header titles of a mailbox list's sections.
struct SectionTitles {
    private var titles: [MailboxSection: String] = [:]

    subscript(section: MailboxSection) -> String? { titles[section] }

    /// Takes `sections`' titles and returns the sections that stay in the list under a new title: only their headers
    /// need redrawing. A section coming or going changes no other section's header, so it redraws none.
    mutating func update(to sections: [MailboxViewModel.Section]) -> [MailboxSection] {
        let new = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.title) })
        let retitled = sections.compactMap { section in
            titles[section.id].flatMap { $0 == section.title ? nil : section.id }
        }
        titles = new
        return retitled
    }
}
