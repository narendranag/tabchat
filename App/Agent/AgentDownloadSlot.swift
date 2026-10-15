import CoreServices
import Foundation

/// One download the agent API started and is waiting for: where it goes, and how it ended.
@MainActor
final class AgentDownloadSlot {
    let directory: URL
    var download: ObjectIdentifier?
    var source: URL?
    var finished: URL?
    var failure: String?

    init(directory: URL) {
        self.directory = directory
    }

    /// Marks the file as downloaded from the internet, so Gatekeeper checks it before it opens.
    static func quarantine(_ url: URL, source: URL?) {
        var properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: "Tabchat"
        ]
        if let source, source.scheme == "https" {
            properties[kLSQuarantineDataURLKey as String] = source
        }
        var values = URLResourceValues()
        values.quarantineProperties = properties
        var target = url
        try? target.setResourceValues(values)
    }
}
