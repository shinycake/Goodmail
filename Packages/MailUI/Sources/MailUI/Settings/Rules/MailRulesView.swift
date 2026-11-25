import MailCore
import SwiftUI

/// Where the rules are, in Settings.
struct RulesSection: View {
    let service: MailRules.Service

    var body: some View {
        Section {
            NavigationLink {
                MailRulesView(service: service)
            } label: {
                Text(MailRulesView.title)
            }
        } footer: {
            Text(
                "Rules act on new mail as it arrives: snooze it, file it, flag it, or tell a shortcut.",
                tableName: "Rules", bundle: .module, comment: "Explains mail rules under their Settings row")
        }
    }
}

/// The rules, in the order they run. Add makes one, tapping one changes it, its switch turns it off, Edit reorders
/// them, and swiping removes one.
struct MailRulesView: View {
    @State private var rules: MailRules
    @State private var editing: RuleDraft?

    /// The model is made once for this screen; the service it talks to doesn't change while it shows.
    init(service: MailRules.Service) {
        _rules = State(initialValue: MailRules(service: service))
    }

    static var title: String {
        String(localized: "Rules", table: "Rules", bundle: .module, comment: "Title of the mail rules screen")
    }

    var body: some View {
        content
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .loaded(let all, _) = rules.state {
                    if !all.isEmpty { EditButton() }
                    Button {
                        editing = RuleDraft()
                    } label: {
                        Label {
                            Text("Add Rule", tableName: "Rules", bundle: .module, comment: "Adds a mail rule")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(item: $editing) { draft in
                MailRuleEditor(draft: draft, labelNames: rules.labelNames) { rules.save($0) }
            }
            .alert(
                Text(
                    "Couldn’t Save Rules", tableName: "Rules", bundle: .module,
                    comment: "Alert title when storing the rules failed"),
                isPresented: Binding(
                    get: { rules.saveFailure != nil }, set: { if !$0 { rules.dismissSaveFailure() } })
            ) {
                Button(role: .cancel) {}
            } message: {
                Text(rules.saveFailure ?? "")
            }
            .task { await rules.load() }
    }

    @ViewBuilder private var content: some View {
        switch rules.state {
        case .loading:
            ProgressView()
        case .failed:
            ContentUnavailableView {
                Label {
                    Text(
                        "Couldn’t Load Rules", tableName: "Rules", bundle: .module,
                        comment: "Shown when the rules can't be read")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } actions: {
                Button {
                    Task { await rules.load() }
                } label: {
                    Text("Try Again", tableName: "Rules", bundle: .module, comment: "Reads the rules again")
                }
            }
        case .loaded(let all, _):
            list(all)
        }
    }

    private func list(_ all: [MailRule]) -> some View {
        List {
            Section {
                ForEach(all) { rule in
                    MailRuleRow(rule: rule, edit: RuleDraft(rule).map { draft in { editing = draft } }) {
                        rules.setEnabled($0, for: rule.id)
                    }
                }
                .onDelete { rules.remove(at: $0) }
                .onMove { rules.move(from: $0, to: $1) }
            } footer: {
                if !all.isEmpty { shortcutsHint }
            }
        }
        .overlay {
            if all.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Rules", tableName: "Rules", bundle: .module, comment: "Shown when there are no rules")
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                } description: {
                    shortcutsHint
                } actions: {
                    Button {
                        editing = RuleDraft()
                    } label: {
                        Text("Add Rule", tableName: "Rules", bundle: .module, comment: "Adds a mail rule")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var shortcutsHint: Text {
        Text(
            "Rules run in this order on each new message from someone else. To run a shortcut when mail arrives, give a rule Notify with Keyword, then in Shortcuts make an automation for Goodmail notifications that contain the keyword.",
            tableName: "Rules", bundle: .module, comment: "Explains rule order and how to start a shortcut from a rule")
    }
}

/// One rule: its name, what it does in brief, and its switch. A rule the editor can't show only switches.
private struct MailRuleRow: View {
    let rule: MailRule
    /// Opens the editor, or `nil` for a rule whose condition is more than the editor shows.
    let edit: (() -> Void)?
    let setEnabled: @MainActor (Bool) -> Void

    var body: some View {
        HStack {
            Button {
                edit?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: rule.name)
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .tint(.primary)
            .disabled(edit == nil)
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: setEnabled)) {
                Text(verbatim: rule.name)
            }
            .labelsHidden()
        }
    }

    /// The actions, as "Snooze, Notify with Keyword".
    private var summary: String {
        rule.actions.map { ActionDraft(action: $0).kind.title }.formatted(.list(type: .and))
    }
}
