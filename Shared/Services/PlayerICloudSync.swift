// ∅ 2026 lil org

#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
import CloudKit
import Foundation
import os

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS) || os(tvOS)
import UIKit
#endif

private let playerICloudSyncLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "PlayerICloudSync"
)

@MainActor
final class PlayerICloudSync {

    static let shared = PlayerICloudSync()

    private static let containerIdentifier = "iCloud.org.lil.nft-folder"
    private static let recordType = "PlayerSyncState"
    private static let schemaVersion = 1
    private static let localChangeSyncDelay: TimeInterval = 1.5
    private static let initialRetryDelay: TimeInterval = 5
    private static let maximumRetryDelay: TimeInterval = 60
    private static let activeRemoteRefreshInterval: TimeInterval = 60

    private static let schemaVersionField = "schemaVersion"
    private static let domainField = "domain"
    private static let payloadDataField = "payloadData"
    private static let updatedAtField = "updatedAt"

    private static let allDomains = Set(PlayerSyncDomain.allCases)

    private let progressStore: PlayerViewingProgressStore
    private let bookmarksStore: PlayerBookmarksStore
    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private lazy var database = container.privateCloudDatabase

    private var lifecycleObservers: [NSObjectProtocol] = []
    private var pendingDomains = Set<PlayerSyncDomain>()
    private var pendingSyncTask: Task<Void, Never>?
    private var pendingSyncGeneration: UInt64 = 0
    private var syncTask: Task<Void, Never>?
    private var activeRemoteRefreshTask: Task<Void, Never>?
    private var activeRemoteRefreshGeneration: UInt64 = 0
    private var isStarted = false
    private var retryAttempt = 0
    private var flushCompletionHandlers: [@MainActor () -> Void] = []

    private init(
        progressStore: PlayerViewingProgressStore = .shared,
        bookmarksStore: PlayerBookmarksStore = .shared
    ) {
        self.progressStore = progressStore
        self.bookmarksStore = bookmarksStore
    }

    func start() {
        guard !isStarted else { return }

        isStarted = true
        installLifecycleObservers()
        refreshActiveRemotePollingState()
        Task { [bookmarksStore] in
            await bookmarksStore.prepareSharedSnapshot()
        }
        scheduleSync(for: Self.allDomains, delay: 0)
    }

    func playerProgressDidChange() {
        scheduleLocalSync(for: .viewingProgress)
    }

    func playerContinueViewingStateDidChange() {
        scheduleLocalSync(for: .continueViewingState)
    }

    func playerBookmarksDidChange() {
        scheduleLocalSync(for: .bookmarks)
    }

    func flushPendingPersistenceAndChanges(
        completion: (@MainActor () -> Void)? = nil
    ) async {
        await PlayerPersistenceUpdates.flush()
        flushPendingChanges(completion: completion)
    }

    func flushPendingChanges(completion: (@MainActor () -> Void)? = nil) {
        if let completion {
            flushCompletionHandlers.append(completion)
        }
        guard isStarted else {
            start()
            return
        }
        guard syncTask != nil || !pendingDomains.isEmpty else {
            completeFlushes()
            return
        }

        cancelPendingSyncTask()

        if syncTask == nil {
            startPendingSync()
        }
    }

    private func scheduleLocalSync(for domain: PlayerSyncDomain) {
        guard isStarted else { return }
        scheduleSync(for: [domain], delay: Self.localChangeSyncDelay)
    }

    private func installLifecycleObservers() {
        let notificationCenter = NotificationCenter.default
        lifecycleObservers.append(
            notificationCenter.addObserver(
                forName: didBecomeActiveNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshActiveRemotePollingState()
                    self.scheduleSync(for: Self.allDomains, delay: 0)
                }
            }
        )
        lifecycleObservers.append(
            notificationCenter.addObserver(
                forName: willResignActiveNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.cancelActiveRemoteRefresh()
                }
            }
        )
    }

    private var didBecomeActiveNotificationName: Notification.Name {
#if os(iOS) || os(visionOS) || os(tvOS)
        UIApplication.didBecomeActiveNotification
#elseif os(macOS)
        NSApplication.didBecomeActiveNotification
#endif
    }

    private var willResignActiveNotificationName: Notification.Name {
#if os(iOS) || os(visionOS) || os(tvOS)
        UIApplication.willResignActiveNotification
#elseif os(macOS)
        NSApplication.willResignActiveNotification
#endif
    }

    private func refreshActiveRemotePollingState() {
        if isApplicationActive {
            scheduleActiveRemoteRefreshIfNeeded()
        } else {
            cancelActiveRemoteRefresh()
        }
    }

    private var isApplicationActive: Bool {
#if os(iOS) || os(visionOS) || os(tvOS)
        UIApplication.shared.applicationState == .active
#elseif os(macOS)
        NSApplication.shared.isActive
#endif
    }

    private func scheduleActiveRemoteRefreshIfNeeded() {
        guard activeRemoteRefreshTask == nil else { return }

        let generation = activeRemoteRefreshGeneration
        activeRemoteRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.activeRemoteRefreshInterval))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  activeRemoteRefreshGeneration == generation else {
                return
            }
            activeRemoteRefreshTask = nil
            guard isApplicationActive else { return }
            scheduleSync(for: Self.allDomains, delay: 0)
            scheduleActiveRemoteRefreshIfNeeded()
        }
    }

    private func cancelActiveRemoteRefresh() {
        activeRemoteRefreshGeneration &+= 1
        activeRemoteRefreshTask?.cancel()
        activeRemoteRefreshTask = nil
    }

    private func scheduleSync(for domains: Set<PlayerSyncDomain>, delay: TimeInterval) {
        guard !domains.isEmpty else { return }

        pendingDomains.formUnion(domains)
        cancelPendingSyncTask()

        guard syncTask == nil else { return }

        guard delay > 0 else {
            startPendingSync()
            return
        }

        let generation = pendingSyncGeneration
        pendingSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  pendingSyncGeneration == generation else {
                return
            }
            pendingSyncTask = nil
            startPendingSync()
        }
    }

    private func startPendingSync() {
        guard syncTask == nil else { return }

        let domains = pendingDomains
        pendingDomains = []
        pendingSyncTask = nil

        guard !domains.isEmpty else {
            completeFlushes()
            return
        }

        syncTask = Task { [weak self] in
            guard let self else { return }
            let failedDomains = await syncDomains(domains)
            finishCurrentSync(failedDomains: failedDomains)
        }
    }

    private func cancelPendingSyncTask() {
        pendingSyncGeneration &+= 1
        pendingSyncTask?.cancel()
        pendingSyncTask = nil
    }

    private func finishCurrentSync(failedDomains: Set<PlayerSyncDomain>) {
        syncTask = nil
        let hasQueuedFollowUpWork = !pendingDomains.isEmpty
        pendingDomains.formUnion(failedDomains)

        if failedDomains.isEmpty {
            retryAttempt = 0
        }

        let delay = failedDomains.isEmpty || hasQueuedFollowUpWork ? 0 : nextRetryDelay()

        guard !pendingDomains.isEmpty else {
            completeFlushes()
            return
        }

        let domains = pendingDomains
        pendingDomains = []
        scheduleSync(for: domains, delay: delay)
    }

    private func nextRetryDelay() -> TimeInterval {
        let multiplier = pow(2, Double(retryAttempt))
        let delay = min(Self.initialRetryDelay * multiplier, Self.maximumRetryDelay)
        retryAttempt += 1
        return delay
    }

    private func completeFlushes() {
        let handlers = flushCompletionHandlers
        flushCompletionHandlers = []
        handlers.forEach { $0() }
    }

    private func syncDomains(_ domains: Set<PlayerSyncDomain>) async -> Set<PlayerSyncDomain> {
        let requestedDomains = domains.isEmpty ? Self.allDomains : domains

        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                logUnavailableAccountStatus(accountStatus)
                return retryDomains(for: accountStatus, requestedDomains: requestedDomains)
            }

            let fetchResult = await fetchRemoteRecords(for: requestedDomains)
            let fetchedDomains = requestedDomains.subtracting(fetchResult.failedDomains)
            guard !fetchedDomains.isEmpty else {
                return fetchResult.failedDomains
            }

            let domainsNeedingUpload = await applyRemoteRecords(
                fetchResult.records,
                fetchedDomains: fetchedDomains
            )
            let domainsMissingCloudPayload = Set(fetchedDomains.filter { domain in
                fetchResult.records[domain].flatMap { payloadData(from: $0) } == nil
            })
            let uploadDomains = domainsNeedingUpload.union(
                domainsMissingCloudPayload
            )
            let failedUploadDomains = await uploadLocalSnapshot(
                for: uploadDomains,
                existingRecords: fetchResult.records
            )
            return fetchResult.failedDomains.union(failedUploadDomains)
        } catch {
            playerICloudSyncLogger.warning(
                "Skipping CloudKit sync after error: \(error.localizedDescription, privacy: .public)"
            )
            return requestedDomains
        }
    }

    private func retryDomains(
        for accountStatus: CKAccountStatus,
        requestedDomains: Set<PlayerSyncDomain>
    ) -> Set<PlayerSyncDomain> {
        switch accountStatus {
        case .couldNotDetermine, .temporarilyUnavailable:
            return requestedDomains
        case .available, .noAccount, .restricted:
            return []
        @unknown default:
            return requestedDomains
        }
    }

    private func fetchRemoteRecords(
        for domains: Set<PlayerSyncDomain>
    ) async -> (records: [PlayerSyncDomain: CKRecord], failedDomains: Set<PlayerSyncDomain>) {
        var records: [PlayerSyncDomain: CKRecord] = [:]
        var failedDomains = Set<PlayerSyncDomain>()
        for domain in PlayerSyncDomain.allCases where domains.contains(domain) {
            do {
                records[domain] = try await fetchRecord(for: domain)
            } catch {
                failedDomains.insert(domain)
                playerICloudSyncLogger.warning(
                    "Skipping \(domain.logLabel, privacy: .public) CloudKit fetch after error: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return (records, failedDomains)
    }

    private func fetchRecord(for domain: PlayerSyncDomain) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID(for: domain))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func applyRemoteRecords(
        _ records: [PlayerSyncDomain: CKRecord],
        fetchedDomains: Set<PlayerSyncDomain>
    ) async -> Set<PlayerSyncDomain> {
        var domainsNeedingUpload = Set<PlayerSyncDomain>()

        for domain in PlayerSyncDomain.allCases where fetchedDomains.contains(domain) {
            let result = await mergeRemotePayload(
                records[domain].flatMap { payloadData(from: $0) },
                for: domain
            )
            if result.shouldMirrorLocalValue {
                domainsNeedingUpload.insert(domain)
            }
        }

        return domainsNeedingUpload
    }

    private func mergeRemotePayload(
        _ data: Data?,
        for domain: PlayerSyncDomain
    ) async -> PlayerSyncMergeResult {
        switch domain {
        case .viewingProgress:
            return await progressStore.mergeSyncedProgressData(data)
        case .continueViewingState:
            return await progressStore.mergeSyncedContinueViewingStateData(data)
        case .bookmarks:
            return await bookmarksStore.mergeSyncedBookmarksData(data)
        }
    }

    private func uploadLocalSnapshot(
        for domains: Set<PlayerSyncDomain>,
        existingRecords: [PlayerSyncDomain: CKRecord]
    ) async -> Set<PlayerSyncDomain> {
        var failedDomains = Set<PlayerSyncDomain>()
        for domain in PlayerSyncDomain.allCases where domains.contains(domain) {
            guard let payload = await localPayload(for: domain) else { continue }

            let existingRecord = existingRecords[domain]
            guard existingRecord.flatMap({ payloadData(from: $0) }) != payload else {
                continue
            }

            do {
                try await saveLocalPayload(
                    payload,
                    for: domain,
                    existingRecord: existingRecord
                )
            } catch {
                failedDomains.insert(domain)
                playerICloudSyncLogger.warning(
                    "Skipping \(domain.logLabel, privacy: .public) CloudKit upload after error: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return failedDomains
    }

    private func saveLocalPayload(
        _ payload: Data,
        for domain: PlayerSyncDomain,
        existingRecord: CKRecord?
    ) async throws {
        let record = cloudRecord(
            for: domain,
            payload: payload,
            existingRecord: existingRecord
        )

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let serverRecord = error.serverRecord else {
                throw error
            }

            let mergeResult = await mergeRemotePayload(
                payloadData(from: serverRecord),
                for: domain
            )
            guard !mergeResult.blocksConflictingUpload else { throw error }

            guard let mergedPayload = await localPayload(for: domain) else { return }

            let retryRecord = cloudRecord(
                for: domain,
                payload: mergedPayload,
                existingRecord: serverRecord
            )
            _ = try await database.save(retryRecord)
        }
    }

    private func localPayload(for domain: PlayerSyncDomain) async -> Data? {
        switch domain {
        case .viewingProgress:
            return await progressStore.syncedProgressData
        case .continueViewingState:
            return await progressStore.syncedContinueViewingStateData
        case .bookmarks:
            return await bookmarksStore.syncedBookmarksData
        }
    }

    private func cloudRecord(
        for domain: PlayerSyncDomain,
        payload: Data,
        existingRecord: CKRecord?
    ) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: Self.recordType,
            recordID: recordID(for: domain)
        )
        record[Self.schemaVersionField] = NSNumber(value: Self.schemaVersion)
        record[Self.domainField] = domain.key as NSString
        record[Self.payloadDataField] = payload as NSData
        record[Self.updatedAtField] = Date() as NSDate
        return record
    }

    private func recordID(for domain: PlayerSyncDomain) -> CKRecord.ID {
        CKRecord.ID(recordName: domain.cloudKitRecordName)
    }

    private func payloadData(from record: CKRecord) -> Data? {
        if let data = record[Self.payloadDataField] as? Data {
            return data
        }

        if let data = record[Self.payloadDataField] as? NSData {
            return data as Data
        }

        return nil
    }

    private func logUnavailableAccountStatus(_ status: CKAccountStatus) {
        switch status {
        case .available:
            break
        case .couldNotDetermine:
            playerICloudSyncLogger.info("Skipping CloudKit sync because account status could not be determined")
        case .noAccount:
            playerICloudSyncLogger.info("Skipping CloudKit sync because no iCloud account is available")
        case .restricted:
            playerICloudSyncLogger.info("Skipping CloudKit sync because the iCloud account is restricted")
        case .temporarilyUnavailable:
            playerICloudSyncLogger.info("Skipping CloudKit sync because the iCloud account is temporarily unavailable")
        @unknown default:
            playerICloudSyncLogger.info("Skipping CloudKit sync because the iCloud account status is unknown")
        }
    }

    isolated deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        pendingSyncTask?.cancel()
        activeRemoteRefreshTask?.cancel()
        syncTask?.cancel()
    }
}

private extension CKError {

    var serverRecord: CKRecord? {
        userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
    }
}
#endif
