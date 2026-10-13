import Foundation

enum UnreadParser {
    /// Chat sites put the unread count in the page title: "(3) WhatsApp". Zero when absent.
    static func count(fromTitle title: String) -> Int {
        guard title.hasPrefix("(") else { return 0 }
        let digits = title.dropFirst().prefix { $0.isASCII && $0.isNumber }
        let rest = title.dropFirst(1 + digits.count)
        guard !digits.isEmpty, rest.hasPrefix(")") else { return 0 }
        return Int(digits) ?? 0
    }
}
