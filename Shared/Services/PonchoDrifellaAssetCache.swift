// ∅ 2026 lil org

import Foundation
import os

private let ponchoDrifellaAssetCacheLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-folder",
    category: "PonchoDrifellaMetal"
)

struct PonchoDrifellaAssetURLs {
    let tokenID: Int
    let face: URL
    let foil: URL
    let textureMask: URL
    let grain: URL
    let glitter: URL
}

private struct PonchoDrifellaAssetPaths {
    let face: String
    let foil: String
    let textureMask: String
    let grain = "img/grain.webp"
    let glitter = "img/glitter.png"

    var tokenSpecificPaths: [String] {
        [face, foil, textureMask]
    }

    var allPaths: [String] {
        tokenSpecificPaths + [grain, glitter]
    }

    init(tokenID: Int) {
        face = "drifs/\(tokenID).webp"
        foil = "foils/\(tokenID).webp"
        textureMask = "textures/\(tokenID).webp"
    }
}

final class PonchoDrifellaAssetCache {

    static let shared = PonchoDrifellaAssetCache()

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let baseURL = URL(string: "https://mons.shop/Poncho_Drifella")!
    private let workQueue = DispatchQueue(label: "org.lil.nft-folder.poncho-cache", qos: .utility)
    private var pendingDownloadCompletions = [String: [(Bool) -> Void]]()

    private init() {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootURL = applicationSupportURL.appendingPathComponent("PonchoDrifellaAssets", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var resourceURL = rootURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(resourceValues)
    }

    func loadAssets(for tokenID: Int, completion: @escaping (PonchoDrifellaAssetURLs?) -> Void) {
        let assetURLs = urls(for: tokenID)
        ensureFiles(relativePaths(for: tokenID)) { didSucceed in
            DispatchQueue.main.async {
                completion(didSucceed ? assetURLs : nil)
            }
        }
    }

    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void) {
        let path = assetPaths(for: tokenID).face
        let faceURL = localURL(for: path)
        ensureFiles([path]) { didSucceed in
            DispatchQueue.main.async {
                completion(didSucceed ? faceURL : nil)
            }
        }
    }

    func prefetch(around tokenID: Int, radius: Int) {
        let lowerBound = max(1, tokenID - radius)
        let upperBound = min(PonchoDrifellaCardMetadata.tokenCount, tokenID + radius)
        for id in lowerBound...upperBound where id != tokenID {
            ensureFiles(relativePaths(for: id, includesSharedAssets: false), completion: nil)
        }
    }

    func invalidate(tokenID: Int) {
        workQueue.async {
            for path in self.relativePaths(for: tokenID, includesSharedAssets: false) {
                try? self.fileManager.removeItem(at: self.localURL(for: path))
            }
        }
    }

    private func ensureFiles(_ relativePaths: [String], completion: ((Bool) -> Void)?) {
        let group = DispatchGroup()
        let statusLock = NSLock()
        var didSucceed = true

        for path in relativePaths {
            group.enter()
            ensureFile(path) { success in
                statusLock.lock()
                didSucceed = didSucceed && success
                statusLock.unlock()
                group.leave()
            }
        }

        group.notify(queue: workQueue) {
            completion?(didSucceed)
        }
    }

    private func ensureFile(_ relativePath: String, completion: @escaping (Bool) -> Void) {
        workQueue.async {
            let localURL = self.localURL(for: relativePath)
            if self.hasCachedFile(at: localURL) {
                completion(true)
                return
            }

            if self.pendingDownloadCompletions[relativePath] != nil {
                self.pendingDownloadCompletions[relativePath]?.append(completion)
                return
            }
            self.pendingDownloadCompletions[relativePath] = [completion]

            let remoteURL = self.baseURL.appendingPathComponent(relativePath)
            let task = URLSession.shared.downloadTask(with: remoteURL) { temporaryURL, response, error in
                let didSucceed = self.storeDownloadedFile(
                    from: temporaryURL,
                    response: response,
                    error: error,
                    remoteURL: remoteURL,
                    localURL: localURL
                )
                self.completeDownload(relativePath: relativePath, didSucceed: didSucceed)
            }
            task.resume()
        }
    }

    private func storeDownloadedFile(
        from temporaryURL: URL?,
        response: URLResponse?,
        error: Error?,
        remoteURL: URL,
        localURL: URL
    ) -> Bool {
        guard error == nil,
              let temporaryURL,
              (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            ponchoDrifellaAssetCacheLogger.error(
                "Poncho asset download failed: \(remoteURL.absoluteString, privacy: .public), status: \(statusCode, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            return false
        }

        do {
            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: localURL)
            try fileManager.moveItem(at: temporaryURL, to: localURL)
            return hasCachedFile(at: localURL)
        } catch {
            ponchoDrifellaAssetCacheLogger.error(
                "Poncho asset cache write failed: \(localURL.path, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    private func completeDownload(relativePath: String, didSucceed: Bool) {
        workQueue.async {
            let completions = self.pendingDownloadCompletions.removeValue(forKey: relativePath) ?? []
            completions.forEach { $0(didSucceed) }
        }
    }

    private func urls(for tokenID: Int) -> PonchoDrifellaAssetURLs {
        let paths = assetPaths(for: tokenID)
        return PonchoDrifellaAssetURLs(
            tokenID: tokenID,
            face: localURL(for: paths.face),
            foil: localURL(for: paths.foil),
            textureMask: localURL(for: paths.textureMask),
            grain: localURL(for: paths.grain),
            glitter: localURL(for: paths.glitter)
        )
    }

    private func relativePaths(for tokenID: Int, includesSharedAssets: Bool = true) -> [String] {
        let paths = assetPaths(for: tokenID)
        return includesSharedAssets ? paths.allPaths : paths.tokenSpecificPaths
    }

    private func assetPaths(for tokenID: Int) -> PonchoDrifellaAssetPaths {
        PonchoDrifellaAssetPaths(tokenID: tokenID)
    }

    private func localURL(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    private func hasCachedFile(at url: URL) -> Bool {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return fileSize > 0
    }
}
