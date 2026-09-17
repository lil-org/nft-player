import Foundation
import Network

nonisolated extension Notification.Name {
    static let collectionCoverConnectionRecovered = Notification.Name("CollectionCoverConnectionRecovered")
}

@MainActor
final class CollectionCoverRecovery {
    static let shared = CollectionCoverRecovery()

    private let cache: PersistentCollectionCoverCache
    private var monitor: NWPathMonitor?
    private var wasAvailable: Bool?

    init(cache: PersistentCollectionCoverCache = .shared) {
        self.cache = cache
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            DispatchQueue.main.async { [weak self] in
                self?.update(isAvailable: isAvailable)
            }
        }
        monitor.start(queue: DispatchQueue(label: "org.lil.player.cover-recovery", qos: .utility))
    }

    func update(isAvailable: Bool) {
        let recovered = wasAvailable == false && isAvailable
        wasAvailable = isAvailable
        guard recovered else { return }
        Task { [weak self, cache] in
            await cache.connectionRecovered()
            guard let self, wasAvailable == true else { return }
            NotificationCenter.default.post(name: .collectionCoverConnectionRecovered, object: self)
        }
    }

    isolated deinit {
        monitor?.cancel()
    }
}
