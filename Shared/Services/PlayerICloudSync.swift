// ∅ 2026 lil org

#if os(macOS) || os(iOS)
import Foundation
import os

private let playerICloudSyncLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-folder",
    category: "PlayerICloudSync"
)

final class PlayerICloudSync {

    static let shared = PlayerICloudSync()

    private static let deferredMirrorDelay: TimeInterval = 1.5
    private static let initialSyncFallbackDelay: TimeInterval = 8
    private static let maximumInitialSyncFallbackAttempts = 3
    private static let maximumKeyValueStoreBytes = 850_000
    private static let initialSyncProbeKey = "playerICloudSyncInitialSyncProbe"
    private static let ubiquityIdentityTokenKey = "playerICloudSyncUbiquityIdentityToken"

    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private var changeObserver: NSObjectProtocol?
    private var pendingMirrorDomains = Set<PlayerSyncDomain>()
    private var pendingMirrorWorkItem: DispatchWorkItem?
    private var initialSyncFallbackWorkItem: DispatchWorkItem?
    private var isStarted = false
    private var isApplyingRemoteChange = false
    private var hasCompletedInitialSync = false
    private var hasSeededMissingCloudValues = false
    private var hasUnsynchronizedChanges = false
    private var canSeedMissingCloudValues = false
    private var initialSyncFallbackAttempts = 0

    private enum UbiquityIdentityChange: Equatable {
        case unavailable
        case unchanged
        case firstAvailable
        case changedAccount

        var hasAvailableAccount: Bool {
            self != .unavailable
        }

        var shouldSeedMissingCloudValues: Bool {
            self == .unchanged || self == .firstAvailable
        }
    }

    private enum StoredUbiquityIdentityToken {
        case missing
        case unreadable
        case token(NSObject)
    }

    private struct SyncedPayloadSnapshot {
        private var payloads: [PlayerSyncDomain: Data] = [:]

        subscript(domain: PlayerSyncDomain) -> Data? {
            get { payloads[domain] }
            set { payloads[domain] = newValue }
        }

        var totalByteCount: Int {
            payloads.values.reduce(0) { $0 + $1.count }
        }
    }

    private struct MirrorPlan {
        var domains: Set<PlayerSyncDomain>
        var payloads: SyncedPayloadSnapshot
        var currentPayloads: SyncedPayloadSnapshot
    }

    private init() {}

    func start() {
        guard !isStarted else { return }

        isStarted = true
        let identityChange = refreshUbiquityIdentity()
        canSeedMissingCloudValues = identityChange.shouldSeedMissingCloudValues
        if identityChange == .changedAccount {
            clearLocalSyncedDataForAccountChange()
        }

        changeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: keyValueStore,
            queue: .main
        ) { [weak self] notification in
            self?.keyValueStoreDidChangeExternally(notification)
        }

        if identityChange.hasAvailableAccount {
            writeInitialSyncProbe()
            keyValueStore.synchronize()
        }
        if identityChange.hasAvailableAccount && identityChange != .changedAccount {
            applyRemoteSnapshot()
        }
        if !identityChange.hasAvailableAccount {
            completeInitialSync(seedMissingCloudValues: false)
            return
        }

        scheduleInitialSyncFallback()
    }

    func playerProgressDidChange() {
        scheduleLocalMirror(for: .viewingProgress)
    }

    func playerContinueViewingStateDidChange() {
        scheduleLocalMirror(for: .continueViewingState)
    }

    func playerBookmarksDidChange() {
        guard shouldMirrorLocalChanges else { return }
        mirrorLocalDomainsImmediately([.bookmarks])
    }

    @discardableResult
    func flushPendingChanges(synchronize: Bool = false) -> Bool {
        guard hasAvailableICloudAccount else {
            cancelPendingMirrorDomains()
            return false
        }

        if synchronize && !hasCompletedInitialSync {
            writeInitialSyncProbe()
            keyValueStore.synchronize()
            return false
        }

        let didSetValue = flushPendingMirrorDomains()
        let shouldSynchronize = synchronize && (didSetValue || hasUnsynchronizedChanges)
        if shouldSynchronize && keyValueStore.synchronize() {
            hasUnsynchronizedChanges = false
        }
        return didSetValue
    }

    private var shouldMirrorLocalChanges: Bool {
        isStarted && hasAvailableICloudAccount && !isApplyingRemoteChange
    }

    private var hasAvailableICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func scheduleLocalMirror(for domain: PlayerSyncDomain) {
        guard shouldMirrorLocalChanges else { return }
        scheduleMirrorLocalDomains([domain], delay: Self.deferredMirrorDelay)
    }

    private func refreshUbiquityIdentity() -> UbiquityIdentityChange {
        guard let currentToken = FileManager.default.ubiquityIdentityToken as? NSObject else {
            return .unavailable
        }

        defer {
            storeUbiquityIdentityToken(currentToken)
        }

        switch storedUbiquityIdentityToken() {
        case .missing:
            return .firstAvailable
        case .unreadable:
            playerICloudSyncLogger.warning("Treating unreadable stored iCloud identity as an account change")
            return .changedAccount
        case .token(let storedToken):
            return storedToken.isEqual(currentToken) ? .unchanged : .changedAccount
        }
    }

    private func storedUbiquityIdentityToken() -> StoredUbiquityIdentityToken {
        guard let data = UserDefaults.standard.data(forKey: Self.ubiquityIdentityTokenKey) else {
            return .missing
        }

        if let token = (try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSObject.self],
            from: data
        )) as? NSObject {
            return .token(token)
        }

        if let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
            unarchiver.requiresSecureCoding = false
            defer { unarchiver.finishDecoding() }

            if let token = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject {
                return .token(token)
            }
        }

        return .unreadable
    }

    private func storeUbiquityIdentityToken(_ token: NSObject) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: false
        ) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.ubiquityIdentityTokenKey)
    }

    private func writeInitialSyncProbe() {
        keyValueStore.set(Date().timeIntervalSinceReferenceDate, forKey: Self.initialSyncProbeKey)
    }

    private func clearLocalSyncedDataForAccountChange() {
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        PlayerViewingProgressStore.clearLocalSyncedData()
        PlayerBookmarksStore.clearLocalSyncedData()
    }

    private func keyValueStoreDidChangeExternally(_ notification: Notification) {
        guard let changeReason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber else {
            return
        }

        switch changeReason.intValue {
        case NSUbiquitousKeyValueStoreServerChange:
            applyRemoteSnapshot(changedDomains: changedDomainSet(from: notification))

        case NSUbiquitousKeyValueStoreInitialSyncChange:
            applyRemoteSnapshot()
            completeInitialSync(seedMissingCloudValues: canSeedMissingCloudValues)

        case NSUbiquitousKeyValueStoreAccountChange:
            hasCompletedInitialSync = false
            hasSeededMissingCloudValues = false
            initialSyncFallbackAttempts = 0
            cancelPendingMirrorDomains()
            let identityChange = refreshUbiquityIdentity()
            canSeedMissingCloudValues = identityChange.shouldSeedMissingCloudValues
            if identityChange == .changedAccount {
                clearLocalSyncedDataForAccountChange()
            }
            guard identityChange.hasAvailableAccount else {
                completeInitialSync(seedMissingCloudValues: false)
                return
            }
            writeInitialSyncProbe()
            if identityChange != .changedAccount {
                applyRemoteSnapshot()
            }
            keyValueStore.synchronize()
            scheduleInitialSyncFallback()

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            handleQuotaViolation(changedKeys: changedKeySet(from: notification))

        default:
            break
        }
    }

    private func applyRemoteSnapshot(changedDomains: Set<PlayerSyncDomain>? = nil) {
        let domainsToMirror = remoteMergeDomains(changedDomains: changedDomains)
        mirrorLocalDomainsImmediately(domainsToMirror)
    }

    private func remoteMergeDomains(changedDomains: Set<PlayerSyncDomain>?) -> Set<PlayerSyncDomain> {
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        var domainsToMirror = Set<PlayerSyncDomain>()
        for domain in PlayerSyncDomain.allCases {
            guard changedDomains?.contains(domain) ?? true else { continue }
            guard mergeRemoteValue(for: domain).shouldMirrorLocalValue else { continue }
            domainsToMirror.insert(domain)
        }
        return domainsToMirror
    }

    private func mergeRemoteValue(for domain: PlayerSyncDomain) -> PlayerSyncMergeResult {
        let data = keyValueStore.data(forKey: domain.key)
        switch domain {
        case .viewingProgress:
            return PlayerViewingProgressStore.mergeSyncedProgressData(data)
        case .continueViewingState:
            return PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(data)
        case .bookmarks:
            return PlayerBookmarksStore.mergeSyncedBookmarksData(data)
        }
    }

    private func completeInitialSync(seedMissingCloudValues: Bool) {
        let shouldSeedMissingCloudValues = seedMissingCloudValues && !hasSeededMissingCloudValues
        if shouldSeedMissingCloudValues {
            hasSeededMissingCloudValues = true
        }

        let missingDomains = shouldSeedMissingCloudValues
            ? localDomainsMissingFromICloud()
            : Set<PlayerSyncDomain>()

        guard !hasCompletedInitialSync else {
            mirrorLocalDomainsImmediately(missingDomains)
            return
        }

        initialSyncFallbackWorkItem?.cancel()
        initialSyncFallbackWorkItem = nil
        initialSyncFallbackAttempts = 0

        var domainsToMirror = missingDomains
        domainsToMirror.formUnion(pendingMirrorDomains)
        hasCompletedInitialSync = true
        mirrorLocalDomainsImmediately(domainsToMirror)
    }

    private func localDomainsMissingFromICloud() -> Set<PlayerSyncDomain> {
        Set(PlayerSyncDomain.allCases.filter { domain in
            keyValueStore.object(forKey: domain.key) == nil && localPayload(for: domain) != nil
        })
    }

    private func scheduleInitialSyncFallback() {
        guard !hasCompletedInitialSync else { return }
        guard initialSyncFallbackAttempts < Self.maximumInitialSyncFallbackAttempts else { return }

        initialSyncFallbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.retryInitialSyncAfterFallback()
        }
        initialSyncFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialSyncFallbackDelay, execute: workItem)
    }

    private func retryInitialSyncAfterFallback() {
        guard !hasCompletedInitialSync else { return }

        initialSyncFallbackWorkItem = nil
        initialSyncFallbackAttempts += 1
        writeInitialSyncProbe()
        keyValueStore.synchronize()
        guard initialSyncFallbackAttempts < Self.maximumInitialSyncFallbackAttempts else {
            cancelPendingMirrorDomains()
            return
        }
        scheduleInitialSyncFallback()
    }

    private func changedKeySet(from notification: Notification) -> Set<String>? {
        let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        return changedKeys.map { Set($0) }
    }

    private func changedDomainSet(from notification: Notification) -> Set<PlayerSyncDomain>? {
        changedKeySet(from: notification).map { changedKeys in
            Set(changedKeys.compactMap { PlayerSyncDomain(key: $0) })
        }
    }

    private func handleQuotaViolation(changedKeys: Set<String>?) {
        cancelPendingMirrorDomains()
        hasUnsynchronizedChanges = false
        let keyList = changedKeys?.sorted().joined(separator: ", ") ?? "unknown"
        playerICloudSyncLogger.warning(
            "Skipping iCloud sync retry after quota violation for keys: \(keyList, privacy: .public)"
        )
    }

    private func scheduleMirrorLocalDomains(_ domains: Set<PlayerSyncDomain>, delay: TimeInterval) {
        guard !domains.isEmpty else { return }

        pendingMirrorDomains.formUnion(domains)
        pendingMirrorWorkItem?.cancel()
        guard hasCompletedInitialSync else {
            pendingMirrorWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingMirrorDomains()
        }
        pendingMirrorWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    @discardableResult
    private func flushPendingMirrorDomains() -> Bool {
        guard hasCompletedInitialSync else { return false }

        let domains = pendingMirrorDomains
        cancelPendingMirrorDomains()
        return mirrorLocalDomains(domains)
    }

    private func mirrorLocalDomainsImmediately(_ domains: Set<PlayerSyncDomain>) {
        guard !domains.isEmpty || !pendingMirrorDomains.isEmpty else { return }
        guard hasCompletedInitialSync else {
            pendingMirrorDomains.formUnion(domains)
            pendingMirrorWorkItem?.cancel()
            pendingMirrorWorkItem = nil
            return
        }

        var domainsToMirror = domains
        domainsToMirror.formUnion(pendingMirrorDomains)
        cancelPendingMirrorDomains()
        mirrorLocalDomains(domainsToMirror)
    }

    private func cancelPendingMirrorDomains() {
        pendingMirrorWorkItem?.cancel()
        pendingMirrorWorkItem = nil
        pendingMirrorDomains = []
    }

    @discardableResult
    private func mirrorLocalDomains(_ domains: Set<PlayerSyncDomain>) -> Bool {
        guard !domains.isEmpty else { return false }
        guard let plan = mirrorPlan(for: domains), !plan.domains.isEmpty else { return false }

        var didSetValue = false
        for domain in PlayerSyncDomain.allCases where plan.domains.contains(domain) {
            didSetValue = mirrorData(
                plan.payloads[domain],
                currentData: plan.currentPayloads[domain],
                for: domain
            ) || didSetValue
        }

        if didSetValue {
            hasUnsynchronizedChanges = true
        }

        return didSetValue
    }

    private func mirrorPlan(for domains: Set<PlayerSyncDomain>) -> MirrorPlan? {
        let currentPayloads = currentSyncedPayloads()
        var proposedPayloads = currentPayloads
        var plannedDomains = domains

        for domain in domains {
            proposedPayloads[domain] = localPayload(for: domain)
        }

        for domain in domains {
            guard let maximumPayloadBytes = domain.maximumPayloadBytes,
                  let payload = proposedPayloads[domain],
                  payload.count > maximumPayloadBytes else {
                continue
            }

            playerICloudSyncLogger.warning(
                "Skipping \(domain.logLabel, privacy: .public) iCloud sync because payload is \(payload.count, privacy: .public) bytes"
            )
            plannedDomains.remove(domain)
            proposedPayloads[domain] = currentPayloads[domain]
        }

        if proposedPayloads.totalByteCount > Self.maximumKeyValueStoreBytes,
           let domainToDrop = PlayerSyncDomain.allCases.first(where: {
               plannedDomains.contains($0) && $0.canBeDroppedForTotalQuota
           }) {
            playerICloudSyncLogger.warning(
                "Skipping \(domainToDrop.logLabel, privacy: .public) iCloud sync because total payload would be \(proposedPayloads.totalByteCount, privacy: .public) bytes"
            )
            plannedDomains.remove(domainToDrop)
            proposedPayloads[domainToDrop] = currentPayloads[domainToDrop]
        }

        guard proposedPayloads.totalByteCount <= Self.maximumKeyValueStoreBytes else {
            playerICloudSyncLogger.warning(
                "Skipping player iCloud sync because total payload would be \(proposedPayloads.totalByteCount, privacy: .public) bytes"
            )
            return nil
        }

        return MirrorPlan(
            domains: plannedDomains,
            payloads: proposedPayloads,
            currentPayloads: currentPayloads
        )
    }

    private func currentSyncedPayloads() -> SyncedPayloadSnapshot {
        var snapshot = SyncedPayloadSnapshot()
        for domain in PlayerSyncDomain.allCases {
            snapshot[domain] = keyValueStore.data(forKey: domain.key)
        }
        return snapshot
    }

    private func localPayload(for domain: PlayerSyncDomain) -> Data? {
        switch domain {
        case .viewingProgress:
            return PlayerViewingProgressStore.syncedProgressData
        case .continueViewingState:
            return PlayerViewingProgressStore.syncedContinueViewingStateData
        case .bookmarks:
            return PlayerBookmarksStore.syncedBookmarksData
        }
    }

    private func mirrorData(
        _ data: Data?,
        currentData: Data?,
        for domain: PlayerSyncDomain
    ) -> Bool {
        guard let data else {
            guard domain.removesCloudValueWhenPayloadIsNil,
                  currentData != nil else {
                return false
            }
            keyValueStore.removeObject(forKey: domain.key)
            return true
        }

        guard currentData != data else { return false }
        keyValueStore.set(data, forKey: domain.key)
        return true
    }

    deinit {
        pendingMirrorWorkItem?.cancel()
        initialSyncFallbackWorkItem?.cancel()
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

}
#endif
