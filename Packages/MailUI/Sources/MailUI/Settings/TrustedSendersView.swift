import SwiftUI

/// Where remote images come in from: a link to the senders the reader trusts to always load them.
struct RemoteImagesSection: View {
    var body: some View {
        Section {
            NavigationLink {
                TrustedSendersView(senders: TrustedImageSenders())
            } label: {
                Text(TrustedSendersView.title)
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

/// The senders whose remote images always load, one address a row. Swiping or editing removes one, and their
/// images are blocked again in the mail opened after.
struct TrustedSendersView: View {
    let senders: TrustedImageSenders
    @State private var addresses: [String] = []

    static var title: String {
        String(
            localized: "Trusted Senders", table: "RemoteImages", bundle: .module,
            comment: "Title of the list of senders whose remote images always load")
    }

    var body: some View {
        List {
            if !addresses.isEmpty {
                Section {
                    ForEach(addresses, id: \.self) { address in
                        Text(verbatim: address)
                    }
                    .onDelete { offsets in
                        offsets.map { addresses[$0] }.forEach(senders.distrust)
                        addresses = senders.addresses
                    }
                } footer: {
                    Text(
                        "Images from these senders load as soon as you open their mail.", tableName: "RemoteImages",
                        bundle: .module, comment: "Explains the list of trusted senders")
                }
            }
        }
        .overlay {
            if addresses.isEmpty {
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
                        "To always load a sender’s images, open the menu beside Load Remote Images in their message.",
                        tableName: "RemoteImages", bundle: .module, comment: "Explains how to trust a sender")
                }
            }
        }
        // An empty list draws no grouped background of its own; keep Settings' grey either way.
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            if !addresses.isEmpty { EditButton() }
        }
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { addresses = senders.addresses }
    }
}
