import Foundation

/// A named sign-in. Every profile owns one persistent website data store (cookies, storage);
/// tabs that point at the same profile share a sign-in.
struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String

    var dataStoreID: UUID {
        StableUUID.make(id)
    }
}
