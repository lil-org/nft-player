// ∅ 2026 lil org

import Foundation

nonisolated struct CollectionsGridScrollPosition: Codable, Equatable, Sendable {
    let collectionId: String
    let sourceIndex: Int

    func resolvedSourceIndex(in items: [CollectionCatalogItem]) -> Int? {
        if let collectionIndex = items.firstIndex(where: { $0.id == collectionId }) {
            return collectionIndex
        }
        guard sourceIndex >= 0, sourceIndex < items.count else { return nil }
        return sourceIndex
    }
}

nonisolated enum CollectionsGridLoop {
    static func sourceIndex(
        forDisplayedIndex displayedIndex: Int,
        itemCount: Int
    ) -> Int {
        precondition(displayedIndex >= 0)
        precondition(itemCount > 0)
        return displayedIndex % itemCount
    }

    static func initialDisplayedIndex(startSourceIndex: Int, itemCount: Int) -> Int? {
        guard itemCount > 0,
              startSourceIndex > 0,
              startSourceIndex < itemCount else {
            return nil
        }
        return startSourceIndex
    }

    static func initialGridPassCount(startSourceIndex: Int, itemCount: Int) -> Int {
        initialDisplayedIndex(startSourceIndex: startSourceIndex, itemCount: itemCount) == nil ? 1 : 2
    }

    static func initialCollectionIds(
        in items: [CollectionCatalogItem],
        startSourceIndex: Int,
        limit: Int
    ) -> [String] {
        guard !items.isEmpty, limit > 0 else { return [] }
        return (0..<min(items.count, limit)).map { displayedIndex in
            let sourceIndex = sourceIndex(
                forDisplayedIndex: startSourceIndex + displayedIndex,
                itemCount: items.count
            )
            return items[sourceIndex].id
        }
    }

    static func shouldAppendNextPass(
        forDisplayedIndex displayedIndex: Int,
        itemCount: Int,
        visibleItemCount: Int
    ) -> Bool {
        guard itemCount > 0 else { return false }
        let appendThreshold = min(max(itemCount / 2, 24), itemCount)
        return displayedIndex >= visibleItemCount - appendThreshold
    }
}

nonisolated private final class CollectionsGridScrollMemoryStorage: @unchecked Sendable {
    private let lock = NSLock()
    private let userDefaults = UserDefaults.standard

    func data(forKey key: String) -> Data? {
        lock.withLock { userDefaults.data(forKey: key) }
    }

    func set(_ data: Data, forKey key: String) {
        lock.withLock { userDefaults.set(data, forKey: key) }
    }
}

nonisolated enum CollectionsGridScrollMemory {
    private static let userDefaultsKey = "collectionsGridScrollPosition"
    private static let storage = CollectionsGridScrollMemoryStorage()

    static func load() -> CollectionsGridScrollPosition? {
        guard let data = storage.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CollectionsGridScrollPosition.self, from: data)
    }

    static func save(_ position: CollectionsGridScrollPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        storage.set(data, forKey: userDefaultsKey)
    }

    static func resolvedStartSourceIndex(
        in items: [CollectionCatalogItem],
        savedPosition: CollectionsGridScrollPosition?
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        return savedPosition?.resolvedSourceIndex(in: items) ?? 0
    }
}

@MainActor
final class CollectionsGridScrollMemoryTracker {
    private static let saveDebounceDelay = Duration.milliseconds(350)

    let initialDisplayedIndex: Int?
    let initialGridPassCount: Int

    private let startSourceIndex: Int
    private let items: [CollectionCatalogItem]
    private var realizedDisplayedIndexes = Set<Int>()
    private var pendingPosition: CollectionsGridScrollPosition?
    private var lastSavedPosition: CollectionsGridScrollPosition?
    private var saveTask: Task<Void, Never>?
    private var canTrackRealizedDisplayedIndexes = false
    private var canRememberScrollPosition: Bool

    init(items: [CollectionCatalogItem]) {
        let savedPosition = CollectionsGridScrollMemory.load()
        lastSavedPosition = savedPosition
        self.items = items
        startSourceIndex = CollectionsGridScrollMemory.resolvedStartSourceIndex(
            in: items,
            savedPosition: savedPosition
        )
        initialDisplayedIndex = CollectionsGridLoop.initialDisplayedIndex(
            startSourceIndex: startSourceIndex,
            itemCount: items.count
        )
        initialGridPassCount = CollectionsGridLoop.initialGridPassCount(
            startSourceIndex: startSourceIndex,
            itemCount: items.count
        )
        canRememberScrollPosition = initialDisplayedIndex == nil
    }

    deinit {
        saveTask?.cancel()
        guard let pendingPosition,
              pendingPosition != lastSavedPosition else { return }
        CollectionsGridScrollMemory.save(pendingPosition)
    }

    func restoreWillBegin() {
        canRememberScrollPosition = false
        canTrackRealizedDisplayedIndexes = true
        realizedDisplayedIndexes.removeAll()
    }

    func restoreDidComplete() {
        canRememberScrollPosition = true
        canTrackRealizedDisplayedIndexes = false
        realizedDisplayedIndexes.removeAll()
    }

    func isDisplayedItemRealized(_ displayedIndex: Int) -> Bool {
        canTrackRealizedDisplayedIndexes && realizedDisplayedIndexes.contains(displayedIndex)
    }

    func itemDidAppear(displayedIndex: Int) {
        guard canTrackRealizedDisplayedIndexes else { return }
        realizedDisplayedIndexes.insert(displayedIndex)
    }

    func itemDidDisappear(displayedIndex: Int) {
        guard canTrackRealizedDisplayedIndexes else { return }
        realizedDisplayedIndexes.remove(displayedIndex)
    }

    func initialCollectionIds(limit: Int) -> [String] {
        CollectionsGridLoop.initialCollectionIds(
            in: items,
            startSourceIndex: startSourceIndex,
            limit: limit
        )
    }

    func visibleDisplayedIndexDidChange(_ displayedIndex: Int) {
        guard canRememberScrollPosition,
              !items.isEmpty,
              displayedIndex >= 0 else {
            return
        }

        let sourceIndex = CollectionsGridLoop.sourceIndex(
            forDisplayedIndex: displayedIndex,
            itemCount: items.count
        )
        rememberPosition(
            CollectionsGridScrollPosition(
                collectionId: items[sourceIndex].id,
                sourceIndex: sourceIndex
            )
        )
    }

    func flush() {
        cancelScheduledFlush()
        guard let pendingPosition,
              pendingPosition != lastSavedPosition else {
            self.pendingPosition = nil
            return
        }

        CollectionsGridScrollMemory.save(pendingPosition)
        lastSavedPosition = pendingPosition
        self.pendingPosition = nil
    }

    private func rememberPosition(_ position: CollectionsGridScrollPosition) {
        guard position != lastSavedPosition else {
            pendingPosition = nil
            cancelScheduledFlush()
            return
        }

        guard position != pendingPosition else { return }
        pendingPosition = position
        scheduleFlush()
    }

    private func scheduleFlush() {
        cancelScheduledFlush()

        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.saveDebounceDelay)
            } catch {
                return
            }
            self?.flush()
        }
    }

    private func cancelScheduledFlush() {
        saveTask?.cancel()
        saveTask = nil
    }
}
