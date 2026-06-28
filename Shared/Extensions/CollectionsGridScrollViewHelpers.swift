// ∅ 2026 lil org

import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

private let collectionsGridScrollCoordinateSpaceName = "CollectionsGridScrollCoordinateSpace"

enum CollectionsGridScrollViewRestorer {
    private static let maximumRestoreAttempts = 6

    static func restoreIfNeeded(
        using scrollProxy: ScrollViewProxy,
        tracker: CollectionsGridScrollMemoryTracker,
        hasRestored: Binding<Bool>,
        onRestored: ((Int) -> Void)? = nil
    ) {
        guard !hasRestored.wrappedValue,
              let initialDisplayedIndex = tracker.initialDisplayedIndex else {
            return
        }

        tracker.restoreWillBegin()
        restore(
            displayedIndex: initialDisplayedIndex,
            using: scrollProxy,
            isTargetReady: {
                tracker.isDisplayedItemRealized(initialDisplayedIndex)
            },
            setRestored: {
                tracker.restoreDidComplete()
                hasRestored.wrappedValue = true
            },
            onRestored: onRestored
        )
    }

    private static func restore(
        displayedIndex: Int,
        using scrollProxy: ScrollViewProxy,
        isTargetReady: @escaping () -> Bool,
        setRestored: @escaping () -> Void,
        onRestored: ((Int) -> Void)? = nil
    ) {
        restore(
            displayedIndex: displayedIndex,
            using: scrollProxy,
            isTargetReady: isTargetReady,
            setRestored: setRestored,
            onRestored: onRestored,
            attempt: 1
        )
    }

    private static func restore(
        displayedIndex: Int,
        using scrollProxy: ScrollViewProxy,
        isTargetReady: @escaping () -> Bool,
        setRestored: @escaping () -> Void,
        onRestored: ((Int) -> Void)?,
        attempt: Int
    ) {
        DispatchQueue.main.async {
            withoutAnimation {
                scrollProxy.scrollTo(displayedIndex, anchor: .top)
            }
            DispatchQueue.main.async {
                guard isTargetReady() || attempt >= maximumRestoreAttempts else {
                    restore(
                        displayedIndex: displayedIndex,
                        using: scrollProxy,
                        isTargetReady: isTargetReady,
                        setRestored: setRestored,
                        onRestored: onRestored,
                        attempt: attempt + 1
                    )
                    return
                }
                withoutAnimation {
                    setRestored()
                }
                onRestored?(displayedIndex)
            }
        }
    }

    private static func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}

extension View {
    func collectionsGridScrollMemoryContent() -> some View {
        background {
            GeometryReader { geometryProxy in
                Color.clear.preference(
                    key: CollectionsGridScrollMetricsPreferenceKey.self,
                    value: CollectionsGridScrollMetrics(
                        contentMinY: geometryProxy
                            .frame(in: .named(collectionsGridScrollCoordinateSpaceName))
                            .minY,
                        contentWidth: geometryProxy.size.width
                    )
                )
            }
        }
    }

    func collectionsGridScrollMemoryTracking(
        tracker: CollectionsGridScrollMemoryTracker,
        minimumItemWidth: CGFloat,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat,
        visibleItemCount: Int
    ) -> some View {
        coordinateSpace(name: collectionsGridScrollCoordinateSpaceName)
            .onPreferenceChange(CollectionsGridScrollMetricsPreferenceKey.self) { metrics in
                guard let displayedIndex = metrics?.estimatedDisplayedIndex(
                    minimumItemWidth: minimumItemWidth,
                    columnSpacing: columnSpacing,
                    rowSpacing: rowSpacing,
                    visibleItemCount: visibleItemCount
                ) else {
                    return
                }
                tracker.visibleDisplayedIndexDidChange(displayedIndex)
            }
    }

    func collectionsGridMemoryItem(
        displayedIndex: Int,
        tracker: CollectionsGridScrollMemoryTracker
    ) -> some View {
        onAppear {
            tracker.itemDidAppear(displayedIndex: displayedIndex)
        }
        .onDisappear {
            tracker.itemDidDisappear(displayedIndex: displayedIndex)
        }
    }

    func collectionsGridScrollMemoryRestoration(
        using scrollProxy: ScrollViewProxy,
        tracker: CollectionsGridScrollMemoryTracker,
        hasRestored: Binding<Bool>,
        onRestored: ((Int) -> Void)? = nil
    ) -> some View {
        onAppear {
            CollectionsGridScrollViewRestorer.restoreIfNeeded(
                using: scrollProxy,
                tracker: tracker,
                hasRestored: hasRestored,
                onRestored: onRestored
            )
        }
    }

    func collectionsGridScrollMemoryLifecycleFlush(
        tracker: CollectionsGridScrollMemoryTracker
    ) -> some View {
        modifier(CollectionsGridScrollMemoryLifecycleFlushModifier(tracker: tracker))
    }
}

private struct CollectionsGridScrollMemoryLifecycleFlushModifier: ViewModifier {
    let tracker: CollectionsGridScrollMemoryTracker

    func body(content: Content) -> some View {
#if os(macOS)
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                tracker.flush()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                tracker.flush()
            }
            .onDisappear {
                tracker.flush()
            }
#elseif os(iOS) || os(tvOS) || os(visionOS)
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                tracker.flush()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                tracker.flush()
            }
            .onDisappear {
                tracker.flush()
            }
#else
        content
            .onDisappear {
                tracker.flush()
            }
#endif
    }
}

private struct CollectionsGridScrollMetrics: Equatable {
    let contentMinY: CGFloat
    let contentWidth: CGFloat

    func estimatedDisplayedIndex(
        minimumItemWidth: CGFloat,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat,
        visibleItemCount: Int
    ) -> Int? {
        guard visibleItemCount > 0,
              contentMinY.isFinite,
              contentWidth.isFinite,
              contentWidth > 0,
              minimumItemWidth.isFinite,
              minimumItemWidth > 0,
              columnSpacing.isFinite,
              rowSpacing.isFinite else {
            return nil
        }

        let resolvedColumnSpacing = max(columnSpacing, 0)
        let columnCount = max(
            Int((contentWidth + resolvedColumnSpacing) / (minimumItemWidth + resolvedColumnSpacing)),
            1
        )
        let itemWidth = (
            contentWidth - CGFloat(columnCount - 1) * resolvedColumnSpacing
        ) / CGFloat(columnCount)
        let rowHeight = max(itemWidth + max(rowSpacing, 0), 1)
        let visibleTopOffset = max(-contentMinY, 0)
        let topRow = max(Int(floor(visibleTopOffset / rowHeight)), 0)
        return min(topRow * columnCount, visibleItemCount - 1)
    }
}

private struct CollectionsGridScrollMetricsPreferenceKey: PreferenceKey {
    static var defaultValue: CollectionsGridScrollMetrics? = nil

    static func reduce(
        value: inout CollectionsGridScrollMetrics?,
        nextValue: () -> CollectionsGridScrollMetrics?
    ) {
        value = nextValue() ?? value
    }
}
