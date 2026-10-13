import Foundation

/// What one tab reports: a number, or just "something is unread" for sites that show only a dot.
struct Unread: Equatable, Sendable {
    var count = 0
    var dot = false

    static let none = Unread()

    var hasUnread: Bool {
        count >= 1 || dot
    }
}

enum UnreadParser {
    /// Chat sites put the unread count in the page title: "(3) WhatsApp". Zero when absent.
    static func count(fromTitle title: String) -> Int {
        guard title.hasPrefix("(") else { return 0 }
        let digits = title.dropFirst().prefix { $0.isASCII && $0.isNumber }
        let rest = title.dropFirst(1 + digits.count)
        guard !digits.isEmpty, rest.hasPrefix(")") else { return 0 }
        return Int(digits) ?? 0
    }

    /// A count if the title has one; otherwise a title starting with "•" or "*" (a favicon-dot style
    /// site) means "unread, number unknown".
    static func parse(title: String) -> Unread {
        let count = count(fromTitle: title)
        if count > 0 {
            return Unread(count: count)
        }
        let trimmed = title.drop { $0.isWhitespace }
        return Unread(count: 0, dot: trimmed.hasPrefix("•") || trimmed.hasPrefix("*"))
    }
}

/// The totals shown outside the window: Dock badge and menu bar icon.
enum UnreadSummary {
    /// Dot-only tabs count as zero here.
    static func total(_ values: some Collection<Unread>) -> Int {
        values.reduce(0) { $0 + $1.count }
    }

    static func anyUnread(_ values: some Collection<Unread>) -> Bool {
        values.contains { $0.hasUnread }
    }

    /// The Dock badge text; nil clears it.
    static func dockLabel(total: Int) -> String? {
        total > 0 ? String(total) : nil
    }

    /// The menu bar line for one tab: "Name", "Name  (3)" or "Name  •".
    static func menuTitle(name: String, unread: Unread) -> String {
        if unread.count >= 1 {
            return "\(name)  (\(unread.count))"
        }
        return unread.dot ? "\(name)  •" : name
    }
}
