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
