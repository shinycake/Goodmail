import MailCore
import SwiftUI

/// Adds a trust rule or changes one, in a sheet over the list. Save keeps the rule the fields make and closes.
struct ImageTrustRuleEditor: View {
    /// What the sheet opened for: a new rule, or one from the list to change.
    enum Purpose: Identifiable, Hashable {
        case add
        case edit(ImageTrustRule)

        var id: Self { self }
    }

    let purpose: Purpose
    let save: (ImageTrustRule) -> Void
    @State private var draft: ImageTrustRuleDraft
    @Environment(\.dismiss) private var dismiss

    init(purpose: Purpose, save: @escaping (ImageTrustRule) -> Void) {
        self.purpose = purpose
        self.save = save
        // Seeds the fields once, from the rule being changed.
        switch purpose {
        case .add: _draft = State(initialValue: ImageTrustRuleDraft())
        case .edit(let rule): _draft = State(initialValue: ImageTrustRuleDraft(rule))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $draft.kind) {
                        Text("Domain", tableName: "RemoteImages", bundle: .module, comment: "Rule kind: a whole domain")
                            .tag(ImageTrustRule.Kind.domain)
                        Text("Sender", tableName: "RemoteImages", bundle: .module, comment: "Rule kind: one address")
                            .tag(ImageTrustRule.Kind.sender)
                    } label: {
                        Text(
                            "Rule Type", tableName: "RemoteImages", bundle: .module,
                            comment: "Label of the choice between trusting a domain or one sender")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField(text: $draft.text, prompt: prompt) { label }
                        .keyboardType(draft.kind == .sender ? .emailAddress : .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(draft.kind == .sender ? .emailAddress : nil)
                        .submitLabel(.done)
                        .onSubmit(commit)
                    if draft.kind == .domain {
                        Toggle(isOn: includesSubdomains) {
                            Text(
                                "Include Subdomains", tableName: "RemoteImages", bundle: .module,
                                comment: "Toggle: a domain rule also covers the domains under it")
                        }
                    }
                } footer: {
                    footer
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: commit).disabled(draft.rule == nil)
                }
            }
        }
    }

    private func commit() {
        guard let rule = draft.rule else { return }
        save(rule)
        dismiss()
    }

    private var includesSubdomains: Binding<Bool> {
        Binding {
            draft.subdomains == .included
        } set: {
            draft.subdomains = $0 ? .included : .excluded
        }
    }

    private var title: Text {
        switch purpose {
        case .add:
            Text("Add Rule", tableName: "RemoteImages", bundle: .module, comment: "Title of the sheet adding a rule")
        case .edit:
            Text("Edit Rule", tableName: "RemoteImages", bundle: .module, comment: "Title of the sheet changing a rule")
        }
    }

    private var label: Text {
        switch draft.kind {
        case .sender:
            Text("Address", tableName: "RemoteImages", bundle: .module, comment: "Field label: the trusted address")
        case .domain:
            Text("Domain", tableName: "RemoteImages", bundle: .module, comment: "Field label: the trusted domain")
        }
    }

    private var prompt: Text {
        switch draft.kind {
        case .sender: Text(verbatim: "name@example.com")
        case .domain: Text(verbatim: "example.com")
        }
    }

    @ViewBuilder private var footer: some View {
        if let rule = draft.rule, rule.isPublicMail {
            Label {
                Text(
                    "Anyone can get an address at \(rule.value), so this loads images from strangers too.",
                    tableName: "RemoteImages", bundle: .module,
                    comment: "Warns that a domain rule for a public mail provider trusts everyone there")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } else {
            switch draft.kind {
            case .sender:
                Text(
                    "Images load in mail from this address.", tableName: "RemoteImages", bundle: .module,
                    comment: "Explains a sender rule")
            case .domain:
                switch draft.subdomains {
                case .included:
                    Text(
                        "Images load in mail from any address at this domain or under it, like news.example.com.",
                        tableName: "RemoteImages", bundle: .module, comment: "Explains a domain rule with subdomains")
                case .excluded:
                    Text(
                        "Images load in mail from any address at exactly this domain.", tableName: "RemoteImages",
                        bundle: .module, comment: "Explains a domain rule without subdomains")
                }
            }
        }
    }
}
