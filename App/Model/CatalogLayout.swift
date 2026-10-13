import Foundation

/// Which catalog cards the Add service sheet shows, and in what order. The custom website card is
/// not part of this: it is always last and cannot be hidden.
enum CatalogLayout {
    /// `services` in the user's order: ids listed in `order` first, the rest in catalog order.
    static func ordered(_ services: [Service], order: [String]) -> [Service] {
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return services.enumerated().sorted { lhs, rhs in
            switch (position[lhs.element.id], position[rhs.element.id]) {
            case let (left?, right?): left < right
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// What the sheet lists: everything in order while editing, otherwise without the hidden ones.
    static func visible(_ services: [Service], order: [String], hidden: [String], editing: Bool) -> [Service] {
        let all = ordered(services, order: order)
        return editing ? all : all.filter { !hidden.contains($0.id) }
    }

    /// The new full order after dragging `id` onto the card `target`.
    static func moved(_ id: String, before target: String, services: [Service], order: [String]) -> [String] {
        var ids = ordered(services, order: order).map(\.id)
        guard id != target, let from = ids.firstIndex(of: id) else { return ids }
        ids.remove(at: from)
        ids.insert(id, at: ids.firstIndex(of: target) ?? ids.count)
        return ids
    }

    static func toggled(_ id: String, in hidden: [String]) -> [String] {
        hidden.contains(id) ? hidden.filter { $0 != id } : hidden + [id]
    }
}
