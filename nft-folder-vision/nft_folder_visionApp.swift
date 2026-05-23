// ∅ 2026 lil org

import SwiftUI

@main
struct nft_folder_visionApp: App {
    var body: some Scene {
        WindowGroup(id: WindowId.collections) {
            VisionCollectionsView()
        }
    }
}
