// ∅ 2026 lil org

import Foundation

struct MetadataStorage {
    
    private static let fileManager = FileManager.default
    private static let collectionAddressOnlyBlockExplorerAddresses: Set<String> = [
        "0xc2276a4a03e7c2e2fa122692b07a870eff43cf51",
    ]
    
    static func detailedMetadata(nftFilePath: String) -> DetailedTokenMetadata? {
        if let fileId = fileId(path: nftFilePath), var url = URL.minimalMetadataDirectory(filePath: nftFilePath) {
            url.append(path: fileId)
            if let data = try? Data(contentsOf: url), let minimal = try? JSONDecoder().decode(MinimalTokenMetadata.self, from: data),
               var url = URL.detailedMetadataDirectory(filePath: nftFilePath) {
                url.append(path: fileNameCorrespondingTo(minimalMetadata: minimal))
                if let data = try? Data(contentsOf: url),
                   let metadata = try? JSONDecoder().decode(DetailedTokenMetadata.self, from: data) {
                    return metadata
                }
            }
        }
        return nil
    }
    
    static func storeOriginalSuggestedItem(_ item: SuggestedItem, wallet: WatchOnlyWallet) {
        guard let data = try? JSONEncoder().encode(item),
              let url = URL.suggestedItemOnDisk(wallet: wallet) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    static func recoverCollectionIfPossible(folderPath: String) -> WatchOnlyWallet? {
        guard let files = try? fileManager.contentsOfDirectory(atPath: folderPath) else { return nil }
        
        if let url = URL.suggestedItemOnDisk(folderPath: folderPath),
           let data = try? Data(contentsOf: url),
           let suggestedItem = try? JSONDecoder().decode(SuggestedItem.self, from: data) {
            var walletName = suggestedItem.name
            if WalletsService.shared.hasWallet(folderName: suggestedItem.name) {
                walletName += " " + suggestedItem.address.suffix(4)
            }
            let wallet = WatchOnlyWallet(address: suggestedItem.address, name: walletName, avatar: nil, projectId: suggestedItem.abId ?? suggestedItem.collectionId, chain: suggestedItem.chain, collections: [CollectionInfo(name: suggestedItem.name, network: suggestedItem.network, chain: suggestedItem.chain)])
            return wallet
        }
        
        for name in files {
            guard !name.hasPrefix(".") else { continue }
            let filePath = folderPath + "/" + name
            if let minimalMetadata = minimalMetadata(filePath: filePath),
               let detailedMetadata = detailedMetadata(nftFilePath: filePath),
               minimalMetadata.collectionAddress == detailedMetadata.collectionAddress,
               let collectionName = detailedMetadata.collectionName, name.contains(collectionName) {
                let collectionInfo = CollectionInfo(name: collectionName, network: detailedMetadata.network, chain: detailedMetadata.chain)
                return WatchOnlyWallet(address: detailedMetadata.collectionAddress, name: collectionName, avatar: nil, projectId: nil, chain: detailedMetadata.chain, collections: [collectionInfo])
            } else {
                return nil
            }
        }
        return nil
    }
    
    static func has(contentHash: UInt64, addressDirectoryURL: URL) -> Bool {
        if var url = URL.hashedMetadataDirectory(addressDirectoryURL: addressDirectoryURL) {
            url.append(path: String(contentHash))
            return fileManager.fileExists(atPath: url.path)
        } else {
            return false
        }
    }
    
    static func hasSomethingFor(detailedMetadata: DetailedTokenMetadata, addressDirectoryURL: URL) -> Bool {
        if var url = URL.detailedMetadataDirectory(addressDirectoryURL: addressDirectoryURL) {
            url.append(path: fileNameCorrespondingTo(minimalMetadata: detailedMetadata.minimalMetadata()))
            return fileManager.fileExists(atPath: url.path)
        } else {
            return false
        }
    }
    
    static func store(contentHash: UInt64, addressDirectoryURL: URL) {
        if var url = URL.hashedMetadataDirectory(addressDirectoryURL: addressDirectoryURL) {
            url.append(path: String(contentHash))
            try? Data().write(to: url)
        }
    }
    
    static func store(detailedMetadata: DetailedTokenMetadata, correspondingTo minimal: MinimalTokenMetadata, addressDirectoryURL: URL) {
        if let data = try? JSONEncoder().encode(detailedMetadata), var url = URL.detailedMetadataDirectory(addressDirectoryURL: addressDirectoryURL) {
            url.append(path: fileNameCorrespondingTo(minimalMetadata: minimal))
            try? data.write(to: url)
        }
    }
    
    static func store(minimalMetadata: MinimalTokenMetadata, filePath: String) {
        if let fileId = fileId(path: filePath),
           let data = try? JSONEncoder().encode(minimalMetadata),
           var url = URL.minimalMetadataDirectory(filePath: filePath) {
            url.append(path: fileId)
            try? data.write(to: url)
        }
    }
    
    static func minimalMetadata(filePath: String) -> MinimalTokenMetadata? {
        if let fileId = fileId(path: filePath), var url = URL.minimalMetadataDirectory(filePath: filePath) {
            url.append(path: fileId)
            if let data = try? Data(contentsOf: url),
               let metadata = try? JSONDecoder().decode(MinimalTokenMetadata.self, from: data) {
                return metadata
            }
        }
        return nil
    }
    
    static func nftURL(filePath: String, gallery: NftGallery) -> URL? {
        if let metadata = minimalMetadata(filePath: filePath) {
            return nftURL(metadata: metadata, gallery: gallery)
        } else {
            return nil
        }
    }
    
    private static func nftURL(metadata: MinimalTokenMetadata, gallery: NftGallery) -> URL? {
        let tokenId = gallery == .blockExplorer && collectionAddressOnlyBlockExplorerAddresses.contains(metadata.collectionAddress.lowercased())
            ? nil
            : metadata.tokenId
        let url = gallery.url(network: metadata.network, chain: metadata.chain, collectionAddress: metadata.collectionAddress, tokenId: tokenId)
        return url
    }
    
    private static func fileNameCorrespondingTo(minimalMetadata: MinimalTokenMetadata) -> String {
        return "\(minimalMetadata.network.rawValue)\(minimalMetadata.collectionAddress)\(minimalMetadata.tokenId)"
    }
    
    private static func fileId(path: String) -> String? {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let number = attributes[.systemFileNumber] as? UInt {
            return String(number)
        } else {
            return nil
        }
    }
    
}
