import MailCore
import SwiftUI

/// Where remote images come in from: a link to the rules that always load them.
struct RemoteImagesSection: View {
    var body: some View {
        Section {
            NavigationLink {
                ImageTrustRulesView(store: ImageTrustRules())
            } label: {
                Text(ImageTrustRulesView.title)
            }
        } header: {
            Text(
                "Remote Images", tableName: "RemoteImages", bundle: .module,
                comment: "Settings section for loading images from the web in mail")
        } footer: {
            Text(
                "Remote images can tell senders when you open their mail. Goodmail loads them only when you ask, and always for trusted senders.",
                tableName: "RemoteImages", bundle: .module, comment: "Explains why remote images are blocked")
        }
    }
}

/// The rules that always load remote images, domains then senders. Add makes one by hand, tapping a rule changes it,
/// and swiping or editing removes one; images it matched are blocked again in the mail opened after.
struct ImageTrustRulesView: View {
    let store: ImageTrustRules
    @State private var rules: [ImageTrustRule] = []
    @State private var editing: ImageTrustRuleEditor.Purpose?

    static var title: String {
        String(
            localized: "Trusted Senders", table: "RemoteImages", bundle: .module,
            comment: "Title of the list of senders and domains whose remote images always load")
    }

    var body: some View {
        List {
            section(.domain) {
                Text("Domains", tableName: "RemoteImages", bundle: .module, comment: "Header of the trusted domains")
            }
            section(.sender) {
                Text("Senders", tableName: "RemoteImages", bundle: .module, comment: "Header of the trusted senders")
            }
        }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(
                            "No Trusted Senders", tableName: "RemoteImages", bundle: .module,
                            comment: "Shown when no sender's remote images always load")
                    } icon: {
                        Image(systemName: "checkmark.shield")
                    }
                } description: {
                    Text(
                        "To always load images from a sender or their domain, open the menu beside Load Remote Images in their message, or tap Add.",
                        tableName: "RemoteImages", bundle: .module, comment: "Explains how to trust a sender or domain")
                }
            }
        }
        // An empty list draws no grouped background of its own; keep Settings' grey either way.
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            if !rules.isEmpty { EditButton() }
            Button {
                editing = .add
            } label: {
                Label {
                    Text("Add", tableName: "RemoteImages", bundle: .module, comment: "Adds a trust rule by hand")
                } icon: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { purpose in
            ImageTrustRuleEditor(purpose: purpose) { rule in
                switch purpose {
                case .add: store.add(rule)
                case .edit(let old): store.replace(old, with: rule)
                }
                rules = store.all
            }
        }
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rules = store.all }
    }

    /// The rules of one kind, under `header`; nothing when there are none.
    @ViewBuilder
    private func section(_ kind: ImageTrustRule.Kind, header: () -> Text) -> some View {
        let shown = rules.filter { $0.kind == kind }
        if !shown.isEmpty {
            Section {
                ForEach(shown, id: \.self) { rule in
                    Button {
                        editing = .edit(rule)
                    } label: {
                        ImageTrustRuleRow(rule: rule)
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    offsets.map { shown[$0] }.forEach(store.remove)
                    rules = store.all
                }
            } header: {
                header()
            }
        }
    }
}

/// One rule: its address or domain, and whether a domain reaches its subdomains.
private struct ImageTrustRuleRow: View {
    let rule: ImageTrustRule

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: rule.value)
            if case .domain(_, .included) = rule {
                Text(
                    "Includes subdomains", tableName: "RemoteImages", bundle: .module,
                    comment: "Under a trusted domain whose subdomains are trusted too"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if rule.isPublicMail {
                Label {
                    Text(
                        "Anyone can get an address here", tableName: "RemoteImages", bundle: .module,
                        comment: "Under a trusted domain that is a public mail provider")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
