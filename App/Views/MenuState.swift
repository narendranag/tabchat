import Combine
import Foundation

/// The tab list for the Services menu. SwiftUI's `Commands` do not reliably redraw when an
/// `@Observable` model changes, but they do when an `ObservableObject` they hold publishes, so
/// `AppModel` pushes the list here on every save.
@MainActor
final class MenuState: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    @Published private(set) var items: [Item] = []

    func update(from tabs: [Tab]) {
        let next = tabs.map { Item(id: $0.id, name: $0.displayName) }
        if next != items {
            items = next
        }
    }
}
