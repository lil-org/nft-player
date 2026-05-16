// ∅ 2026 lil org

import Foundation

class WalletDownloader {
    
    private var didStudy = false
    private var completion: () -> Void
    
    private lazy var fileDownloader = FileDownloader { [weak self] in
        if self?.didStudy == true {
            self?.completion()
        }
    }
    
    init(completion: @escaping () -> Void) {
        self.completion = completion
    }
    
    func study(wallet: WatchOnlyWallet) {
        let shouldGoThroughNfts = processBundledTokens(wallet: wallet)
        
        if shouldGoThroughNfts {
            goThroughNfts(wallet: wallet)
        } else {
            didStudy = true
        }
    }
    
    private func processBundledTokens(wallet: WatchOnlyWallet) -> Bool {
        guard let collection = wallet.collections?.first else { return true }
        if let bundledTokens = SuggestedItemsService.bundledTokens(collectionId: wallet.id),
           let walletRootDirectory = URL.nftDirectory(wallet: wallet, createIfDoesNotExist: false) {
            var tasks = [DownloadFileTask]()
            for item in bundledTokens.items.shuffled() {
                let name: String?
                let contentRepresentations: [ContentRepresentation]
                if let sh = item.sh {
                    guard let content = ContentRepresentation(url: "https://cdn.simplehash.com/assets/\(sh)", size: nil, mimeType: nil, knownKind: nil) else { continue }
                    contentRepresentations = [content]
                    name = item.name
                } else if let url = item.url {
                    guard let content = ContentRepresentation(url: url, size: nil, mimeType: nil, knownKind: nil) else { continue }
                    contentRepresentations = [content]
                    name = item.name
                } else {
                    if let imageContent = ContentRepresentation(url: "https://media-proxy.artblocks.io/\(wallet.address)/\(item.id).png",
                                                                size: nil, mimeType: nil, knownKind: .image) {
                        contentRepresentations = [imageContent]
                        if let knownName = item.name {
                            name = knownName
                        } else if let projectId = wallet.projectId, item.id.hasPrefix(projectId), item.id != projectId {
                            let cleanId = item.id.dropFirst(projectId.count).drop(while: { $0 == "0" })
                            name = collection.name + " #" + (cleanId.isEmpty ? "0" : cleanId)
                        } else {
                            name = nil
                        }
                    } else {
                        continue
                    }
                }
                
                let detailedMetadata = DetailedTokenMetadata(name: name, collectionName: collection.name, collectionAddress: wallet.address, tokenId: item.id, chain: wallet.chain, network: collection.network, tokenStandard: nil, contentRepresentations: contentRepresentations)
                guard !MetadataStorage.hasSomethingFor(detailedMetadata: detailedMetadata, addressDirectoryURL: walletRootDirectory) else { continue }
                let minimalMetadata = MinimalTokenMetadata(tokenId: item.id, collectionAddress: wallet.address, chain: wallet.chain, network: collection.network)
                let downloadTask = DownloadFileTask(walletRootDirectory: walletRootDirectory, minimalMetadata: minimalMetadata, detailedMetadata: detailedMetadata)
                tasks.append(downloadTask)
            }
            fileDownloader.addTasks(tasks, wallet: wallet)
            return false
        } else {
            return true
        }
    }
    
    private func goThroughNfts(wallet: WatchOnlyWallet) {
        goThroughNfts(wallet: wallet, nextCursor: nil)
    }
    
    private func nextStepForNfts(wallet: WatchOnlyWallet, nextCursor: String?) {
        if nextCursor != nil {
            goThroughNfts(wallet: wallet, nextCursor: nextCursor)
        } else {
            didStudy = true
            if !fileDownloader.hasPendingTasks {
                completion()
            }
        }
    }
    
    private func goThroughNfts(wallet: WatchOnlyWallet, nextCursor: String?) {
        let completion: (NftsResponse?) -> Void = { [weak self] result in
            guard let nfts = result?.nfts, !nfts.isEmpty else {
                self?.nextStepForNfts(wallet: wallet, nextCursor: nil)
                return
            }
            
            self?.processResultNfts(nfts, wallet: wallet)
            
            if let nextCursor = result?.next {
                self?.nextStepForNfts(wallet: wallet, nextCursor: nextCursor)
            }
        }
        
        if wallet.isCollection {
            RawNftsApi.get(contract: wallet.address, network: downloadNetwork(for: wallet), nextCursor: nextCursor, completion: completion)
        } else {
            RawNftsApi.get(owner: wallet.address, network: downloadNetwork(for: wallet), nextCursor: nextCursor, completion: completion)
        }
    }
    
    private func processResultNfts(_ nfts: [OpenSeaNft], wallet: WatchOnlyWallet) {
        guard let destination = URL.nftDirectory(wallet: wallet, createIfDoesNotExist: false) else { return }
        let network = downloadNetwork(for: wallet)
        let tasks = nfts.map { nft -> DownloadFileTask in
            let minimal = MinimalTokenMetadata(tokenId: nft.identifier, collectionAddress: nft.contract, chain: wallet.chain, network: network)
            let detailed = nft.detailedMetadata(network: network, chain: wallet.chain)
            return DownloadFileTask(walletRootDirectory: destination, minimalMetadata: minimal, detailedMetadata: detailed)
        }
        fileDownloader.addTasks(tasks, wallet: wallet)
    }

    private func downloadNetwork(for wallet: WatchOnlyWallet) -> Network {
        wallet.collections?.first?.network ?? wallet.chain?.network ?? .mainnet
    }
    
    deinit {
        fileDownloader.invalidateAndCancel()
    }
    
}
