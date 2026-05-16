// ∅ 2026 lil org

import Foundation

struct WalletsService {
    
    enum WalletsServiceError: Error {
        case notAnAddress
    }
    
    private init() {}
    static let shared = WalletsService()
    private let urlSession = URLSession.shared
    private let fileManager = FileManager.default
    
    var wallets: [WatchOnlyWallet] {
        return SharedDefaults.watchWallets.reversed()
    }
    
    func updateWithWallets(_ wallets: [WatchOnlyWallet]) {
        SharedDefaults.watchWallets = wallets.reversed()
    }
    
    func addWallet(_ wallet: WatchOnlyWallet, skipCollectionCheck: Bool) {
        SharedDefaults.addWallet(wallet)
        if !skipCollectionCheck {
            checkIfCollection(wallet: wallet)
        }
    }
    
    func removeWallet(_ wallet: WatchOnlyWallet) {
        SharedDefaults.removeWallet(wallet)
        Defaults.cleanupForWallet(wallet)
    }
    
    func removeWallet(id: String) {
        if let toRemove = wallets.first(where: { $0.id == id }) {
            removeWallet(toRemove)
        }
    }
    
    func resolveENS(_ input: String, completion: @escaping (Result<EnsResponse, WalletsServiceError>) -> Void) {
        guard isEthAddress(input),
              let path = input.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.ensideas.com/ens/resolve/\(path)") else {
            completion(.failure(.notAnAddress))
            return
        }
        let dataTask = urlSession.dataTask(with: URLRequest(url: url)) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error == nil, (200...299).contains(statusCode), let data = data, let response = try? JSONDecoder().decode(EnsResponse.self, from: data) {
                DispatchQueue.main.async { completion(.success(response)) }
            } else {
                DispatchQueue.main.async { completion(.failure(.notAnAddress)) }
            }
        }
        dataTask.resume()
    }
    
    func wallet(folderName: String) -> WatchOnlyWallet? {
        return wallets.first(where: { $0.folderDisplayName == folderName })
    }
    
    func hasWallet(folderName: String) -> Bool {
        return SharedDefaults.hasWallet(folderName: folderName)
    }
    
    func isEthAddress(_ input: String) -> Bool {
        if input.hasSuffix(".eth") { return true }
        guard input.hasPrefix("0x") && input.count == 42 else { return false }
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let addressSet = CharacterSet(charactersIn: String(input.dropFirst(2)))
        return hexSet.isSuperset(of: addressSet)
    }
    
    func checkFoldersForNewWalletsAndRemovedWallets(onNewWallet: @escaping (WatchOnlyWallet) -> Void) -> [WatchOnlyWallet] {
        guard let path = URL.nftDirectory?.path, let files = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        var knownWallets = Set(wallets)
        for name in files {
            guard !name.hasPrefix(".") else { continue }
            if let known = knownWallets.first(where: { $0.folderDisplayName == name }) {
                knownWallets.remove(known)
            } else if isEthAddress(name) {
                resolveENS(name) { result in
                    switch result {
                    case .success(let response):
                        let wallet = WatchOnlyWallet(address: response.address, name: response.name, avatar: response.avatar, projectId: nil, chain: nil, collections: nil)
                        self.addWallet(wallet, skipCollectionCheck: false)
                        renameFolder(path: path, name: name, wallet: wallet)
                        FolderIcon.set(for: wallet)
                        onNewWallet(wallet)
                    case .failure:
                        return
                    }
                }
            } else if let collectionFolder = MetadataStorage.recoverCollectionIfPossible(folderPath: path + "/" + name) {
                self.addWallet(collectionFolder, skipCollectionCheck: true)
            }
        }
        
        for remaining in knownWallets {
            removeWallet(id: remaining.id)
        }
        return Array(knownWallets)
    }
    
    func checkIfCollection(wallet: WatchOnlyWallet) {
        guard let path = URL.nftDirectory?.path else { return }
        RawNftsApi.getCollectionInfo(contract: wallet.address) { response in
            if let response = response {
                let collections = [CollectionInfo(name: response.name.isEmpty ? response.collection : response.name, network: .mainnet, chain: nil)]
                
                guard var collectionName = collections.first?.name else { return }
                if hasWallet(folderName: collectionName) {
                    collectionName += " " + wallet.address.suffix(4)
                }
                
                let updatedWallet = WatchOnlyWallet(address: wallet.address, name: collectionName, avatar: wallet.avatar, projectId: wallet.projectId, chain: nil, collections: collections)
                DispatchQueue.main.async {
                    var walletsUpdate = wallets
                    if let index = walletsUpdate.firstIndex(where: { $0.id == updatedWallet.id }) {
                        renameFolder(path: path, name: wallet.folderDisplayName, wallet: updatedWallet)
                        walletsUpdate[index] = updatedWallet
                        updateWithWallets(walletsUpdate)
                        AllDownloadsManager.shared.downloadCollections(collectionsWallet: updatedWallet, initialWallet: wallet)
                        NotificationCenter.default.post(name: .walletsUpdate, object: nil)
                    }
                }
            }
        }
    }
    
    private func renameFolder(path: String, name: String, wallet: WatchOnlyWallet) {
        let old = path + "/" + name
        let new = path + "/" + wallet.folderDisplayName
        do {
            try self.fileManager.moveItem(atPath: old, toPath: new)
        } catch {
            if self.fileManager.fileExists(atPath: new) == true {
                try? self.fileManager.removeItem(atPath: old)
            }
        }
    }
    
}
