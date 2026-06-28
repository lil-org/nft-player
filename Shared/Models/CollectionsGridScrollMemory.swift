// ∅ 2026 lil org

import Foundation

struct CollectionsGridScrollPosition: Codable, Equatable {
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

enum CollectionsGridLoop {
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

enum CollectionsGridScrollMemory {
    private static let userDefaultsKey = "collectionsGridScrollPosition"
    private static let userDefaults = UserDefaults.standard

    static func load() -> CollectionsGridScrollPosition? {
        guard let data = userDefaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CollectionsGridScrollPosition.self, from: data)
    }

    static func save(_ position: CollectionsGridScrollPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        userDefaults.set(data, forKey: userDefaultsKey)
    }

    static func resolvedStartSourceIndex(
        in items: [CollectionCatalogItem],
        savedPosition: CollectionsGridScrollPosition?
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        return savedPosition?.resolvedSourceIndex(in: items) ?? 0
    }
}

final class CollectionsGridScrollMemoryTracker {
    private static let saveDebounceDelay: DispatchTimeInterval = .milliseconds(350)

    let initialDisplayedIndex: Int?
    let initialGridPassCount: Int

    private let startSourceIndex: Int
    private let items: [CollectionCatalogItem]
    private var realizedDisplayedIndexes = Set<Int>()
    private var pendingPosition: CollectionsGridScrollPosition?
    private var lastSavedPosition: CollectionsGridScrollPosition?
    private var saveWorkItem: DispatchWorkItem?
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
        flush()
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

        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceDelay, execute: workItem)
    }

    private func cancelScheduledFlush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
    }
}
