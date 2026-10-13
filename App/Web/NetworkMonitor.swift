import Network

/// Reports when connectivity returns so failed tabs can retry at once, not on the next timer tick.
final class NetworkMonitor: Sendable {
    private let monitor = NWPathMonitor()

    func start(onSatisfied: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                onSatisfied()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.narendranag.tabchat.network"))
    }
}
