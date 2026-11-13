import Foundation

/// One page of a Graph collection, with the link to the next when there is one.
struct GraphPage<Item: Decodable>: Decodable {
    let value: [Item]
    let nextLink: URL?

    private enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

/// A mail folder, as `mailFolders` lists it.
struct GraphFolder: Decodable {
    let id: String
    let displayName: String
    let childFolderCount: Int?
}

/// One round of a delta query. Graph ends every round with exactly one link: the next page, or the delta link that
/// picks up next time.
struct GraphDeltaPage<Item: Decodable>: Decodable {
    enum Link {
        case next(URL)
        case delta(URL)
    }

    let value: [Item]
    let link: Link

    private enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
        case deltaLink = "@odata.deltaLink"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode([Item].self, forKey: .value)
        if let next = try container.decodeIfPresent(URL.self, forKey: .nextLink) {
            link = .next(next)
        } else {
            link = .delta(try container.decode(URL.self, forKey: .deltaLink))
        }
    }
}

/// A message as a delta query reports it: changed, or removed from the folder.
struct DeltaMessage: Decodable {
    struct Removed: Decodable {
        let reason: String?
    }

    let id: String
    let conversationId: String?
    let removed: Removed?

    private enum CodingKeys: String, CodingKey {
        case id, conversationId
        case removed = "@removed"
    }
}

/// A message as the modified-since query lists it.
struct ModifiedMessage: Decodable {
    static let fields = "id,conversationId,lastModifiedDateTime"

    let id: String
    let conversationId: String?
    let lastModifiedDateTime: Date
}
