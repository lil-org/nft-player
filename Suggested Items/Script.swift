// ∅ 2026 lil org

import Foundation

struct Script: Codable {
    
    var id: String { address + abId }
    
    let address: String
    let name: String
    let abId: String
    let chain: Chain?
    let value: String
    let kind: Kind
    let instructions: String?
    let screensaverFileName: String?
    let nftPlayerDisplayTuning: String?
    
    enum Kind: String, Codable {
        case svg, js, p5js100, regl, twemoji, three, tone, paper, p5js190
        case ponchoDrifellaNative = "native.poncho-drifella"
    }
    
    var screensaverUrl: URL? {
        if let fileName = screensaverFileName {
            return URL(string: "https://github.com/lil-org/screen-savers/releases/download/1.0.0/\(fileName).zip")
        } else {
            return nil
        }
    }
    
}
