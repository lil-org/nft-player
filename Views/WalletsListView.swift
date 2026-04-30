// ∅ 2026 lil org

import Cocoa
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct WalletsListView: View {
    
    private let uuid = UUID().uuidString
    
    @State private var isWaiting = false
    @State private var showAddWalletPopup: Bool
    @State private var showSettingsPopup = false
    @State private var newWalletAddress = ""
    @State private var wallets = WalletsService.shared.wallets
    @State private var suggestedItems = SuggestedItemsService.visibleItems
    @State private var didAppear = false
    @State private var isDownloading = false
    @State private var downloadsStatuses = AllDownloadsManager.shared.statuses
    @State private var draggingIndex: Int? = nil
    @State private var currentDropDestination: Int? = nil
    @State private var showMorePreferences = false
    @State private var cancellables = Set<AnyCancellable>()
    
    init(showAddWalletPopup: Bool) {
        self.showAddWalletPopup = showAddWalletPopup
    }
    
    var body: some View {
        Group {
            if wallets.isEmpty && didAppear && suggestedItems.isEmpty {
                Button(Strings.newFolder, action: {
                    showAddWalletPopup = true
                }).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    createGrid().frame(maxWidth: .infinity)
                }.background(Color(nsColor: .controlBackgroundColor))
                    .toolbar {
                        ToolbarItemGroup(placement: .principal) {
                            
                        }
                        
                        ToolbarItemGroup() {
                            Spacer()
                            if isDownloading {
                                Button(action: {
                                    AllDownloadsManager.shared.stopAllDownloads()
                                }) {
                                    Images.pause
                                }.frame(width: 23)
                            }
                            
                            Button(action: {
                                showSettingsPopup = true
                            }) {
                                Images.gearshape
                            }.frame(width: 23)
                            
                            Button(action: {
                                if let nftDirectory = URL.nftDirectory {
                                    NSWorkspace.shared.open(nftDirectory)
                                }
                            }) {
                                Images.openFinder
                            }.frame(width: 23)
                            
                            Button(action: {
                                showPlayer(id: nil)
                            }) {
                                Images.shuffle
                            }.frame(width: 23)
                            
                            Button(action: {
                                showAddWalletPopup = true
                            }) {
                                Images.plus
                            }.frame(width: 23)
                        }
                    }
            }
        }.sheet(isPresented: $showAddWalletPopup) {
            VStack {
                Text(Strings.newFolder).fontWeight(.medium)
                TextField(Strings.addressOrEns, text: $newWalletAddress)
                HStack {
                    Spacer()
                    Button(Strings.cancel, action: {
                        showAddWalletPopup = false
                        newWalletAddress = ""
                        isWaiting = false
                    })
                    
                    if isWaiting {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.5)
                    } else {
                        Button(Strings.ok, action: {
                            resolveEnsAndAddWallet()
                        }).keyboardShortcut(.defaultAction)
                    }
                }
            }.frame(width: 230).padding()
        }.sheet(isPresented: $showSettingsPopup) {
            VStack {
                PreferencesView()
                HStack {
                    Button(action: {
                        showMorePreferences.toggle()
                    }) {
                        Images.ellipsis
                    }.popover(isPresented: $showMorePreferences, arrowEdge: .bottom) {
                        VStack(spacing: 13) {
                            Button(Strings.rateOnTheAppStore) {
                                NSWorkspace.shared.open(URL.writeAppStoreReview)
                                showSettingsPopup = false
                                showMorePreferences = false
                            }
                            Button(Strings.restoreHiddenItems) {
                                restoreHiddenItems()
                                showSettingsPopup = false
                                showMorePreferences = false
                            }
                            Button(Strings.eraseAllContent) {
                                eraseAllContent()
                                showSettingsPopup = false
                                showMorePreferences = false
                            }.buttonStyle(BorderlessButtonStyle()).foregroundColor(.red)
                        }.frame(height: 81).padding()
                    }
                    Spacer()
                    Button(Strings.ok, action: {
                        showSettingsPopup = false
                    }).keyboardShortcut(.defaultAction)
                }
            }.frame(width: 230).padding()
        }.onAppear() {
            NotificationCenter.default.publisher(for: .walletsUpdate)
                .sink { _ in
                    updateDisplayedWallets()
                }
                .store(in: &cancellables)
            
            NotificationCenter.default.publisher(for: .downloadsStatusUpdate)
                .sink { _ in
                    updateDisplayedWallets()
                }
                .store(in: &cancellables)
            
            NotificationCenter.default.publisher(for: .updateAnotherVisibleWalletsList)
                .sink { notification in
                    if let anotherId = notification.object as? String, anotherId != uuid {
                        updateDisplayedWallets()
                    }
                }
                .store(in: &cancellables)
            
            NotificationCenter.default.publisher(for: .updateAnotherVisibleSuggestions)
                .sink { notification in
                    if let anotherId = notification.object as? String, anotherId != uuid {
                        suggestedItems = SuggestedItemsService.visibleItems
                    }
                }
                .store(in: &cancellables)
            
            updateIsDownloading()
            didAppear = true
        }.onDisappear() {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func openFolderForWallet(_ wallet: WatchOnlyWallet, noAutoPlayer: Bool) {
        guard noAutoPlayer || !autoStartPlayer(id: wallet.id) else { return }
        if let nftDirectory = URL.nftDirectory(wallet: wallet, createIfDoesNotExist: true) {
            NSWorkspace.shared.open(nftDirectory)
        }
        AllDownloadsManager.shared.prioritizeDownloads(wallet: wallet)
    }
    
    private func hardReset(wallet: WatchOnlyWallet) {
        AllDownloadsManager.shared.stopDownloads(wallet: wallet)
        if let nftDirectory = URL.nftDirectory(wallet: wallet, createIfDoesNotExist: false) {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: nftDirectory)
            Defaults.cleanupForWallet(wallet)
            if let _ = URL.nftDirectory(wallet: wallet, createIfDoesNotExist: true) {
                FolderIcon.set(for: wallet)
                AllDownloadsManager.shared.startDownloads(wallet: wallet)
                if !wallet.isCollection {
                    WalletsService.shared.checkIfCollection(wallet: wallet)
                }
            }
        }
    }
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 100), spacing: 0)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(wallets.indices, id: \.self) { index in
                item(for: wallets[index], index: index).onDrag {
                    self.draggingIndex = index
                    return NSItemProvider(object: String(wallets[index].id) as NSString)
                }
                .onDrop(of: [UTType.text], delegate: WalletDropDelegate(uuid: uuid,
                                                                        wallets: $wallets,
                                                                        sourceIndex: $draggingIndex,
                                                                        destinationIndex: Binding.constant(IndexSet(integer: index)),
                                                                        currentDropDestination: $currentDropDestination))
            }
            
            ForEach(suggestedItems) { item in
                ZStack {
                    Image(item.id).resizable().scaledToFill().clipped().aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
                        .onTapGesture {
                            didSelectSuggestedItem(item, noAutoPlayer: false)
                        }
                    VStack {
                        if TokenGenerator.canGenerate(id: item.id) {
                            HStack {
                                Spacer()
                                Images.canGenerateIndicator.shadow(color: .black, radius: 7).foregroundStyle(.white).frame(width: 27, height: 27).onTapGesture {
                                    didSelectSuggestedItem(item, noAutoPlayer: false)
                                }
                            }
                        }
                        Spacer()
                        gridItemText(item.name) {
                            didSelectSuggestedItem(item, noAutoPlayer: false)
                        }
                    }
                }.contextMenu { suggestedItemContextMenu(item: item) }
            }
        }
        return grid
    }
    
    func item(for wallet: WatchOnlyWallet, index: Int) -> some View {
        let status = downloadsStatuses[wallet] ?? .notDownloading
        let isDestination = currentDropDestination == index
        let item = ZStack {
            WalletImageView(wallet: wallet)
                .aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
                .border(isDestination ? Color.blue : Color.clear, width: 2)
                .onTapGesture {
                    openFolderForWallet(wallet, noAutoPlayer: false)
                }
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        Rectangle().foregroundColor(.clear).contentShape(Rectangle())
                        if status == .downloading {
                            Circle().frame(width: 27, height: 27).foregroundStyle(.regularMaterial)
                            Images.pause.foregroundStyle(.white).overlay(FirstMouseView())
                        } else {
                            Images.sync.shadow(color: .black, radius: 7).foregroundStyle(.white.opacity(0.77))
                        }
                    }
                    .frame(width: 34, height: 34)
                    .onTapGesture {
                        switch status {
                        case .downloading:
                            AllDownloadsManager.shared.stopDownloads(wallet: wallet)
                        case .notDownloading:
                            AllDownloadsManager.shared.startDownloads(wallet: wallet)
                        }
                    }
                }
                Spacer()
                gridItemText(wallet.listDisplayName) {
                    openFolderForWallet(wallet, noAutoPlayer: false)
                }
            }
        }.contextMenu { walletContextMenu(wallet: wallet, status: status) }
        return item
    }
    
    private func gridItemText(_ text: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.system(size: 10, weight: .regular)).lineLimit(2)
                .foregroundColor(.white)
                .padding(.horizontal, 1)
                .background(Color.black.opacity(0.7)).cornerRadius(3)
                .padding(.leading, 4).padding(.bottom, 3).onTapGesture {
                    onTap()
                }
            Spacer()
        }
    }
    
    private func showPlayer(id: String?) {
        Navigator.shared.showPlayer(model: PlayerModel(specificCollectionId: id, notTokenId: nil))
    }
    
    private func eraseAllContent() {
        guard let url = URL.nftDirectory else { return }
        AllDownloadsManager.shared.stopAllDownloads()
        try? FileManager.default.removeItem(at: url)
        Defaults.eraseAllContent()
        SharedDefaults.eraseAllContent()
        _ = URL.nftDirectory
        updateDisplayedWallets()
        restoreHiddenItems()
    }
    
    private func restoreHiddenItems() {
        suggestedItems = SuggestedItemsService.restoredSuggestedItems(usersWallets: wallets)
        NotificationCenter.default.post(name: .updateAnotherVisibleSuggestions, object: uuid)
    }
    
    private func suggestedItemContextMenu(item: SuggestedItem) -> some View {
        Group {
            Text(item.name)
            Divider()
            Button(Strings.viewinFinder, action: {
                didSelectSuggestedItem(item, noAutoPlayer: true)
            })
            Button(Strings.hideFromHere, action: {
                removeAndDoNotSuggestAnymore(item: item)
            })
        }
    }
    
    private func walletContextMenu(wallet: WatchOnlyWallet, status: AllDownloadsManager.Status) -> some View {
        Group {
            Text(wallet.listDisplayName)
            Divider()
            switch status {
            case .downloading:
                Button(Strings.pause, action: {
                    AllDownloadsManager.shared.stopDownloads(wallet: wallet)
                })
            case .notDownloading:
                Button(Strings.sync, action: {
                    AllDownloadsManager.shared.startDownloads(wallet: wallet)
                })
            }
            Divider()
            Button(Strings.viewinFinder, action: {
                openFolderForWallet(wallet, noAutoPlayer: true)
            })
            Button(Strings.viewOnOpensea, action: {
                if let galleryURL = NftGallery.opensea.url(wallet: wallet) {
                    DispatchQueue.main.async { NSWorkspace.shared.open(galleryURL) }
                }
            })
            
            if let projectId = wallet.projectId, wallet.isArtBlocks {
                Button(Strings.viewOnArtBlocks, action: {
                    if let url = URL(string: "https://live.artblocks.io/\(wallet.address)/\(projectId)") {
                        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                    }
                })
            }
            
            Divider()
            Button(Strings.hardReset, action: {
                hardReset(wallet: wallet)
            })
            Button(Strings.removeFolder, action: {
                WalletsService.shared.removeWallet(wallet)
                AllDownloadsManager.shared.stopDownloads(wallet: wallet)
                if let path = URL.nftDirectory(wallet: wallet, createIfDoesNotExist: false)?.path {
                    try? FileManager.default.removeItem(atPath: path)
                }
                updateDisplayedWallets()
            })
        }
    }
    
    private func autoStartPlayer(id: String) -> Bool {
        if TokenGenerator.canGenerate(id: id) {
            Navigator.shared.showPlayer(model: PlayerModel(specificCollectionId: id, notTokenId: nil))
            return true
        } else {
            return false
        }        
    }
    
    private func didSelectSuggestedItem(_ item: SuggestedItem, noAutoPlayer: Bool) {
        guard noAutoPlayer || !autoStartPlayer(id: item.id) else { return }
        
        let collections = [CollectionInfo(name: item.name, network: item.network, chain: item.chain)]
        let projectId = item.abId ?? item.collectionId
        
        var walletName = item.name
        if WalletsService.shared.hasWallet(folderName: item.name) {
            walletName += " " + item.address.suffix(4)
        }
        
        let wallet = WatchOnlyWallet(address: item.address, name: walletName, avatar: nil, projectId: projectId, chain: item.chain, collections: collections)
        addWallet(wallet, skipCollectionCheck: true)
        if let image = NSImage(named: item.id) {
            AvatarService.setAvatar(wallet: wallet, image: image)
        }
        DispatchQueue.main.async {
            openFolderForWallet(wallet, noAutoPlayer: true)
        }
        removeAndDoNotSuggestAnymore(item: item)
        MetadataStorage.storeOriginalSuggestedItem(item, wallet: wallet)
    }
    
    private func removeAndDoNotSuggestAnymore(item: SuggestedItem) {
        suggestedItems.removeAll(where: { item.id == $0.id })
        SuggestedItemsService.doNotSuggestAnymore(item: item)
        NotificationCenter.default.post(name: .updateAnotherVisibleSuggestions, object: uuid)
    }
    
    private func addWallet(_ wallet: WatchOnlyWallet, skipCollectionCheck: Bool) {
        WalletsService.shared.addWallet(wallet, skipCollectionCheck: skipCollectionCheck)
        FolderIcon.set(for: wallet)
        updateDisplayedWallets()
        AllDownloadsManager.shared.startDownloads(wallet: wallet)
    }
    
    private func resolveEnsAndAddWallet() {
        guard WalletsService.shared.isEthAddress(newWalletAddress) else { return }
        let knownSuggestedItems = SuggestedItemsService.suggestedItems(address: newWalletAddress)
        if knownSuggestedItems.isEmpty {
            isWaiting = true
            WalletsService.shared.resolveENS(newWalletAddress) { result in
                if case .success(let response) = result {
                    if showAddWalletPopup {
                        let wallet = WatchOnlyWallet(address: response.address, name: response.name, avatar: response.avatar, projectId: nil, chain: nil, collections: nil)
                        addWallet(wallet, skipCollectionCheck: false)
                    }
                    showAddWalletPopup = false
                    newWalletAddress = ""
                    isWaiting = false
                } else {
                    isWaiting = false
                }
            }
        } else if let item = knownSuggestedItems.randomElement() {
            if let wallet = wallets.first(where: { $0.id == item.id }) {
                openFolderForWallet(wallet, noAutoPlayer: false)
            } else {
                didSelectSuggestedItem(item, noAutoPlayer: false)
            }
            showAddWalletPopup = false
            newWalletAddress = ""
        }
    }
    
    private func updateDisplayedWallets() {
        wallets = WalletsService.shared.wallets
        downloadsStatuses = AllDownloadsManager.shared.statuses
        updateIsDownloading()
    }
    
    private func updateIsDownloading() {
        isDownloading = downloadsStatuses.contains(where: { $0.value == .downloading })
    }
    
}

struct WalletDropDelegate: DropDelegate {
    
    let uuid: String
    
    @Binding var wallets: [WatchOnlyWallet]
    @Binding var sourceIndex: Int?
    @Binding var destinationIndex: IndexSet
    @Binding var currentDropDestination: Int?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let source = sourceIndex, let destination = destinationIndex.first else { return false }
        let finalDestination = source <= destination ? destination + 1 : destination
        wallets.move(fromOffsets: IndexSet(integer: source), toOffset: finalDestination)
        WalletsService.shared.updateWithWallets(wallets)
        NotificationCenter.default.post(name: .updateAnotherVisibleWalletsList, object: uuid)
        return true
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [UTType.text])
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if sourceIndex != destinationIndex.first {
            currentDropDestination = destinationIndex.first
        }
        return DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) {
        if destinationIndex.first == currentDropDestination {
            currentDropDestination = nil
        }
    }
    
}
