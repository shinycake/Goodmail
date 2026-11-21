import MailCore
import SwiftUI

/// Makes a smart mailbox or changes one, in a sheet: its name, its symbol, and what it holds, the VIPs for the VIPs
/// box and conditions joined by All or Any for any other, with the rules editor's rows. Save is on once every value
/// reads.
struct SmartMailboxEditor: View {
    let labelNames: [String]
    let save: (SmartMailbox, _ vips: VIPList?) -> Void
    @State private var draft: SmartMailboxDraft
    @Environment(\.dismiss) private var dismiss

    init(draft: SmartMailboxDraft, labelNames: [String], save: @escaping (SmartMailbox, _ vips: VIPList?) -> Void) {
        self.labelNames = labelNames
        self.save = save
        // Seeds the fields once, from the box being changed, a search, or a new one.
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SwiftUI.TextField(text: $draft.name, prompt: Self.namePrompt) { Self.namePrompt }
                }
                Section {
                    SymbolGrid(symbol: $draft.symbol)
                } header: {
                    Text(
                        "Symbol", tableName: "SmartMailboxes", bundle: .module,
                        comment: "Header above the symbols a smart mailbox can show")
                }
                switch draft.contents {
                case .vips(let addresses):
                    VIPSection(addresses: Binding(get: { addresses }, set: { draft.contents = .vips($0) }))
                case .conditions(let joiner, let conditions):
                    ConditionsSection(
                        joiner: Binding(get: { joiner }, set: { draft.contents = .conditions($0, conditions) }),
                        conditions: Binding(get: { conditions }, set: { draft.contents = .conditions(joiner, $0) }),
                        labelNames: labelNames)
                }
            }
            .navigationTitle(
                Text("Smart Mailbox", tableName: "SmartMailboxes", bundle: .module, comment: "Title of the editor")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        guard let box = draft.smartMailbox else { return }
                        save(box, draft.vips)
                        dismiss()
                    }
                    .disabled(draft.smartMailbox == nil)
                }
            }
        }
    }

    private static var namePrompt: Text {
        Text("Name", tableName: "SmartMailboxes", bundle: .module, comment: "Placeholder: a smart mailbox's name")
    }
}

/// The symbols to pick from, the picked one filled in.
private struct SymbolGrid: View {
    @Binding var symbol: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach(SmartMailboxSymbols.all, id: \.self) { name in
                let isOn = name == symbol
                Button {
                    symbol = name
                } label: {
                    Image(systemName: name)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: .circle)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// The conditions, as the rules editor shows a rule's.
private struct ConditionsSection: View {
    @Binding var joiner: RuleDraft.Joiner
    @Binding var conditions: [ConditionDraft]
    let labelNames: [String]

    var body: some View {
        Section {
            Picker(selection: $joiner) {
                Text("All", tableName: "Rules", bundle: .module, comment: "Every condition must hold")
                    .tag(RuleDraft.Joiner.all)
                Text("Any", tableName: "Rules", bundle: .module, comment: "One condition is enough")
                    .tag(RuleDraft.Joiner.any)
            } label: {
                Text("Match", tableName: "Rules", bundle: .module, comment: "Whether all or any conditions must hold")
            }
            .pickerStyle(.segmented)
            ForEach($conditions) { $condition in
                ConditionEditorRow(kind: $condition.kind, labelNames: labelNames)
            }
            .onDelete { conditions.remove(atOffsets: $0) }
            Menu {
                ForEach(RuleChoices.conditions, id: \.title) { choice in
                    Button {
                        conditions.append(ConditionDraft(choice.kind))
                    } label: {
                        Label(choice.title, systemImage: choice.symbol)
                    }
                }
            } label: {
                Label {
                    Text("Add Condition", tableName: "Rules", bundle: .module, comment: "Adds a condition to a rule")
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        } header: {
            Text(
                "Conversations That Match", tableName: "SmartMailboxes", bundle: .module,
                comment: "Header above a smart mailbox's conditions")
        } footer: {
            Text(
                "Looks through the mail on this device, apart from Spam and Trash.", tableName: "SmartMailboxes",
                bundle: .module, comment: "Explains where a smart mailbox finds its conversations")
        }
    }
}

/// The VIPs' addresses, with a field to add one.
private struct VIPSection: View {
    @Binding var addresses: [String]
    @State private var typed = ""

    var body: some View {
        Section {
            ForEach(addresses, id: \.self) { address in
                Text(verbatim: address)
            }
            .onDelete { addresses.remove(atOffsets: $0) }
            HStack {
                SwiftUI.TextField(text: $typed, prompt: Self.prompt) { Self.prompt }
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(add)
                Button(action: add) {
                    Label {
                        Text("Add", tableName: "SmartMailboxes", bundle: .module, comment: "Adds the typed VIP")
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(
                "VIPs", tableName: "SmartMailboxes", bundle: .module,
                comment:
                    "The people the reader marked as VIPs: their smart mailbox, and the header above their addresses")
        } footer: {
            Text(
                "Conversations from these addresses show here, on all your devices.", tableName: "SmartMailboxes",
                bundle: .module, comment: "Explains the VIPs list")
        }
    }

    private static var prompt: Text {
        Text("Email Address", tableName: "SmartMailboxes", bundle: .module, comment: "Placeholder: a VIP's address")
    }

    private func add() {
        let address = typed.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, !addresses.contains(address) else { return }
        addresses.append(address)
        typed = ""
    }
}
