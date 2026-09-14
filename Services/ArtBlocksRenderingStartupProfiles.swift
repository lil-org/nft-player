import CryptoKit
import Foundation

nonisolated enum ArtBlocksRenderingStartupProfiles {
    enum StartupPolicy: Sendable, Equatable {
        case direct
        case calibrated(Profile)
    }

    struct Profile: Codable, Sendable, Equatable {
        let revision: String
        let authoredPixelDensity: Double?
        let coarsePointerPixelDensity: Double?
        let phonePixelDensity: Double?
        let iPadPixelDensity: Double?
        let maximumLogicalDimension: Double?
        let fixedResolution: Bool
    }

    private struct Entry: Sendable {
        let name: String
        let kind: Script.Kind
        let sourceSHA256: String
        let profile: Profile

        init(
            _ name: String,
            _ kind: Script.Kind,
            _ sourceSHA256: String,
            authoredPixelDensity: Double? = nil,
            coarsePointerPixelDensity: Double? = nil,
            phonePixelDensity: Double? = nil,
            iPadPixelDensity: Double? = nil,
            maximumLogicalDimension: Double? = nil,
            fixedResolution: Bool = false
        ) {
            self.name = name
            self.kind = kind
            self.sourceSHA256 = sourceSHA256
            profile = Profile(
                revision: "pass3-startup-v1:" + sourceSHA256,
                authoredPixelDensity: authoredPixelDensity,
                coarsePointerPixelDensity: coarsePointerPixelDensity,
                phonePixelDensity: phonePixelDensity,
                iPadPixelDensity: iPadPixelDensity,
                maximumLogicalDimension: maximumLogicalDimension,
                fixedResolution: fixedResolution
            )
        }
    }

    static func startupPolicy(_ script: Script) -> StartupPolicy {
        guard let entry = validatedEntry(script) else { return .direct }
        return .calibrated(entry.profile)
    }

    static func startupProfile(_ script: Script) -> Profile? {
        guard case let .calibrated(profile) = startupPolicy(script) else { return nil }
        return profile
    }

    static func beforeArtist(_ script: Script) -> String {
        guard let entry = validatedEntry(script), entry.name == "Cushions" else { return "" }
        return """
        (function () {
          if (typeof p5 !== "function" || typeof p5.prototype.loadPixels !== "function") return;
          const hashes = {
            "231000008": "0x4829960114b8d5ecc4d955f289730cdc8f935e7f881c7a987a7b659c3660fdb6",
            "231000020": "0x27ff0d32e24ecd211cc20c2560f7a3fe210a122f7d7b104479dcb82718fb8cb7"
          };
          if (hashes[String(tokenData.tokenId)] !== tokenData.hash) return;
          const original = p5.prototype.loadPixels;
          let pending = true;
          p5.prototype.loadPixels = function () {
            const result = original.apply(this, arguments);
            if (!pending) return result;
            pending = false;
            p5.prototype.loadPixels = original;
            for (let index = 3; index < this.pixels.length; index += 4) {
              if (this.pixels[index] === 254) this.pixels[index] = 255;
            }
            return result;
          };
        }());
        """
    }

    static func afterArtist(_ script: Script) -> String {
        guard let entry = validatedEntry(script) else { return "" }
        if entry.name == "pool party" {
            return """
            timeline_mode = true;
            show_info = false;
            show_pnl = false;
            _vuiHintAlpha = 0;
            """
        }
        if entry.name == "Can you see it" {
            return "windowResized = function () {};"
        }
        if entry.name == "Vahria" {
            return """
            (function () {
              const original = composer.render;
              const size = new THREE.Vector2();
              composer.render = function () {
                renderer.getDrawingBufferSize(size);
                if (this.renderTarget1.width !== size.x || this.renderTarget1.height !== size.y) {
                  this.renderTarget1.setSize(size.x, size.y);
                  this.renderTarget2.setSize(size.x, size.y);
                  this.passes.forEach(function (pass) { pass.setSize(size.x, size.y); });
                }
                return original.apply(this, arguments);
              };
            }());
            """
        }
        guard entry.name == "Gift of Time" else { return "" }
        return """
        (function () {
          if (typeof draw !== "function" || typeof rl !== "function") return;
          const originalDraw = draw;
          draw = function () {
            const result = originalDraw.apply(this, arguments);
            draw = originalDraw;
            requestAnimationFrame(function () { rl(); });
            return result;
          };
        }());
        """
    }

    private static func validatedEntry(_ script: Script) -> Entry? {
        guard script.usesArtBlocksRenderer,
              let entry = entries[script.id],
              entry.name == script.name,
              entry.kind == script.kind else { return nil }
        let digest = SHA256.hash(data: Data(script.value.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return digest == entry.sourceSHA256 ? entry : nil
    }

    private static let entries: [String: Entry] = [
        "0x47a91457a3a1f700097199fd63c039c4784384ab80": Entry("Autopoiesis ", .js, "98234bf23b188f1dfd2ae98499a0dfd98680a67cc180186b389d3d738491af1b", authoredPixelDensity: 1),
        "0x000000098a14b4e08132fd55faec521ab597a0010": Entry("Classical Revival", .p5js100, "6e465c2594aae65e14be45d1ebaa07bf61a9780b1d21f7772465982beba9f2fb", authoredPixelDensity: 1.4, coarsePointerPixelDensity: 1),
        "0x0000000c687f0226eaf0bdb39104fad56738cdf20": Entry("Misbah", .js, "bd81a39ef7f3779f418a34e42471ff43e4e1406cfdbbb72e1fe9e31067d791bc", phonePixelDensity: 1),
        "0x000000412217f67742376769695498074f007b970": Entry("jazz", .p5js100, "052ec69bf996ba5fe8aa3c2316aec046ee4aa606530f3a611aea94f2c046f9d1", authoredPixelDensity: 2),
        "0x000000b394cac6057d87df835bea27844b3e28280": Entry("Transformations du Champ", .three167, "b46cfe862804d2726c909dc5f8a35ee76f902f47fd9aaa30a36dee64c7c8bf32", authoredPixelDensity: 1),
        "0x000000dc68934ed27fd11e32491cdf6717acaf211": Entry("Gift of Time", .p5js190, "408b7a610827c4dd18febf9f0d4da1edd76e6f44bbaa0b10d8ada22ba5861daa", phonePixelDensity: 2, iPadPixelDensity: 2),
        "0x0000f6bc84ab98fbd8fce1f6d047965c723f00000": Entry("Into the Light", .js, "478803fa8b6a2e77466ee89277addf96325300a66ed28273a4222e8315e1b623", fixedResolution: true),
        "0x02f518c529a0002e505000795d00c500eb00534a1": Entry("Geophylla", .three, "06792e6a4a43a1a3aebc5729b566951d67e230a2b78981bacc2936207d2a311c", authoredPixelDensity: 1),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce36761": Entry("Stellaraum", .p5js100, "ec0379a420d11fb71c09948ad4b5d5415da7700b94328270dc4baa4abd9b8ab0", authoredPixelDensity: 1),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367611": Entry("Formation", .p5js100, "cc79c7c2903c079de33e7704d078abc5b8ce8daa6b71a7988c9a82e1e3a3fc70", authoredPixelDensity: 2),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367618": Entry("nth culture", .p5js100, "fe787323775dc4675d942ec175fb5a0b86d766442fbcb284a9ac84a00bac76f7"),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367629": Entry("100 Sunsets", .p5js100, "6348179e69854bfdc270bc44935034002c34d047304b8b6c19d797cf130f385e"),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367638": Entry("Passages", .js, "2919632bb146990ecbfa50e15d96fc2785c9bc36d52c2c0e14eef6fb003573ab", authoredPixelDensity: 2),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367658": Entry("If You Could Do It All Again", .js, "ea54dd70d8e1c3964e9e1d1e5eb9c0b7d3ecff838d2a1d765f91ef710ec49610", authoredPixelDensity: 1),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce36767": Entry("The Nursery", .three, "fe5e31df9c51f26389d9391a4aec2c6d58e94631bdceb95f4f93728cd41d81dd", authoredPixelDensity: 1.5),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367674": Entry("Descent", .js, "77e74e3d42863678bbc26b6d39a50194aa61d4893fa8a3392b1b649a1958ee98"),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367680": Entry("Brava", .p5js100, "816722b3e5526d0a105791c79e9163e14c8bf646f44cb613edcdacdc3101a905", authoredPixelDensity: 1),
        "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367682": Entry("Encore", .js, "a93a6fa3a34226d5cdf2057916bf5da792f4bbce5cc5afcf40f9d29067c18165", authoredPixelDensity: 1),
        "0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e814": Entry("The Collector's Room", .three, "5827ccd876b9660ba48d1f021d19e3d2914c489bae2a4003376744f3fc123312", authoredPixelDensity: 2),
        "0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e82": Entry("Memorias del espacio olvidado", .p5js100, "b4c1d77ebd4101521f20a8f0bedc6bd4d5c6a041b2fbffd011752e9f1313a579", authoredPixelDensity: 2),
        "0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e87": Entry("Deja Vu", .js, "1126b2c4def56f080e13ada26671071de843703c2f8faa3eb685614b272215d5", phonePixelDensity: 1),
        "0x294fed5f1d3d30cfa6fe86a937dc3141eec8bc6d4": Entry("Receive Transmission", .p5js100, "5dea3ea07abac149a484c364a5ea9d2210876200b8e827c6fe2fe2a6daacd6ae", authoredPixelDensity: 2),
        "0x32d4be5ee74376e08038d652d4dc26e62c67f4366": Entry("Décorés", .js, "fe3d8eb0f22d82316630ffe86540d535ec92e89a680bb5c2d49fab48243b5441", authoredPixelDensity: 1),
        "0x70270e65bc37832ef845fa330c2b71501970dab90": Entry("Rain Blooms", .js, "1151ecf02316989b496537701f032931dd48b29f51017c3e98a860978f4be8b8", authoredPixelDensity: 1),
        "0x8cdbd7010bd197848e95c1fd7f6e870aac9b0d3c4": Entry("Trademark", .p5js100, "90b53dffb16d44dae0a0e8f337f550a87d85605d340bdea822645e2820083afb", authoredPixelDensity: 2),
        "0x8db6f700a7c90000f92ac90084ad93a500f1eae00": Entry("Heartbeat", .js, "ad8ad754adefb195f97abe4119df4d5680cfa9f776b2eb433241be1cd907ec34", authoredPixelDensity: 1),
        "0x942bc2d3e7a589fe5bd4a5c6ef9727dfd82f5c8a0": Entry("Friendship Bracelets", .js, "e416e984cfe1e0b73297a90939a8849644dbc9a343b581ce822269b693a76952", authoredPixelDensity: 1),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069389": Entry("Miragem", .p5js100, "01ad61d6b7ea2b0d56117887b605a60b27a6202cbf570f99ae3b8e9fba27cdc3", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069392": Entry("Hyper Drive: A-Side", .p5js100, "047178bb5c1e79fbb65375aa025f60a74a71ce31a469d8d072f73b55039d5e0b", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069398": Entry("Libra", .p5js100, "a4ee3aa9d17da885e57f9ef24b76b8c8c0bda55eec90ed258c88a0b6551d0b97", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069401": Entry("Aragnation", .p5js100, "3facb20dde1e914595f3a6d74a7692ddbdca3fa2c011160e5f7747e3400a8787", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069407": Entry("The Harvest", .p5js100, "30b638bd514ccb97b0ddabe36b05aa10ee3c05ce168df89541f6f80ba41c96c2", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069434": Entry("Voyager", .p5js100, "e8104c2673edbfe66f3e869bbc76edfa2aa86b9f0f883102a7991f9c0db93d13", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069436": Entry("UMK", .p5js100, "214c4fbd1a6b8b09eef6043491af390491b2a58033daf839f62302d1e0c7fd3d", authoredPixelDensity: 1),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069441": Entry("Net Net Net", .p5js100, "71de1b3efaa83960c7af4cdbbbddd66164014092e677ec29eae59095067aec3f", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069444": Entry("Meaningless", .p5js100, "37b2248e24fc525961c7f39e150cd519e9e47908767add000d226b2c804c9e64", authoredPixelDensity: 1),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069459": Entry("Seasky", .p5js100, "e858654fa5acecb9c3994ae6f1aa71928fe7d22a6f7d854aa31cc9d648b2fe44", authoredPixelDensity: 1),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069486": Entry("Proscenium", .js, "f2fc7b982429e22928ffd1268595573385ad342567bbc119c5f3d5c994ae4842", authoredPixelDensity: 1),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069489": Entry("Balance", .js, "4d5152fa263ae2d7d918ffbe4bb20978ff72ba5c3aa06ee135c8c87de6f7cdea", authoredPixelDensity: 2),
        "0x99a9b7c1116f9ceeb1652de04d5969cce509b069493": Entry("Melancholic Magical Maiden", .three, "059ee6c53c962180da7c4ce51525441bb495750b5f2d9420a2eab8a0d5111850", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270104": Entry("Eccentrics", .p5js100, "09d2d27271322944bebedec45077fb7625574ef99bcb5a47177d3dd6b86fd52a", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270136": Entry("SpiroFlakes", .html, "f9a585c3ac2f483e8cf94c464f848f96197b6a04e28f405006a8d41dcdc2052c"),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270139": Entry("Eccentrics 2: Orbits", .p5js100, "94d0019f85c218b4a5ed6ecf87d4f2fc73653eb28c59e001cebdfb7fe0f8662b", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270171": Entry("Himinn", .p5js100, "0c614fe864ddb9232e7c6d5a04517b334d94772dd5fef89db1d40ca041b7464b", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270178": Entry("Beauty in the Hurting", .p5js100, "40a3a4c45d5f93690e1fc57e3a5dc033ae7666e060483ea8ab556b7579bf4fbd", authoredPixelDensity: 2, phonePixelDensity: 1, iPadPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270183": Entry("Quarantine", .three, "70cc8c8ad4aaee795750cb35bbdaecb72d18e07550fd6b50ee7d547e516bbccb", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270197": Entry("Parade", .js, "3badfd101df0598f54b1a750869cf174db74ede5095131694e823802982bdcd6", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270209": Entry("Autology", .js, "4d47e51c058e161128ae1f8fab7e00f81f59008504ef8e5bb8dd73f6705b9559", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270210": Entry("Nebula", .js, "f56a27283e2744b59db7552046323ebdad1945f9091e9622750bfbec2ee6fe2b", phonePixelDensity: 1, iPadPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270215": Entry("Gazers", .p5js100, "9dc23ee4e642a6d4d1f55c27decdaf540f6e66b4ed09a2de3e5820d67acba503", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270231": Entry("Cushions", .p5js100, "05132785b8defb374e43d6384d27ff2d4e1d329ba3b37c2b9369d29c0f43fc67"),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27024": Entry("Pixel Glass", .js, "6742fe91268e92c631b8bb6a262781615868f3ef4a935fd4036de17ef1077777", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27027": Entry("720 Minutes", .js, "c2512a517f5845b35096252396f65ef37ad9e8b9a6bfb1078a72796ebf143589", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270271": Entry("Time travel in a subconscious mind", .p5js100, "7338b69957d8ec64e5a3e7078c7c94706adffb859557a4954088a6b0c7cfb7b6", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270278": Entry("Liquid Ruminations", .p5js100, "0a58885f70f63690e01a9321ee91ea52959b2025870ceeee92dbc5745ccde3fe", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270283": Entry("OnChainChain", .three, "8e86826fe3c1d7a18e939af0c42b3cb194413496b4546dc1b72a89033b47f6eb", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270284": Entry("Ancient Courses of Fictional Rivers", .p5js100, "9ffba47be593ae6ffe6aa1d9a7184c5945a87947ca1e684cb1608f7bcc8c2293", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270317": Entry("the spring begins with the first rainstorm", .p5js100, "300e6c32c61879118bbb637d573b59bf93b130e6c2e6c4ab8d5df7496b0ac261", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270328": Entry("Sudfah", .p5js100, "03f2a86eab52024eca02cb01aa39f5f46b37a0c3a4598ee2af8174a1f677f0d2", phonePixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270329": Entry("Latent Spirits", .p5js100, "7b20abe918b7d2390b5a3a41a9c2d12d3b1f45af37fe442183d3d83cf2ee6a03", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270340": Entry("Vahria", .three, "98b96fce69d12cf063cd8ab5a94348930116df80d6867392e564a504a91b1f02"),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270343": Entry("Balletic", .p5js100, "b1c434faaa860a58448c604d1a9017674efd7858e196ebc7c68223aa6078107f", authoredPixelDensity: 2),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270362": Entry("Erratic", .js, "8567b497a94c5c08cff2b9a8ea8ddaedc28f8fe315a0381d8f90d9cdb9bfe42a", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270366": Entry("Sandaliya", .p5js100, "a1367e748f74481b2d0e0932625b417240d1dde0422fded9930dee0b466d46c3", phonePixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27042": Entry("Void", .js, "f22eb13302adb156372c59f701e63ec08c5eebe1f45cd1567204031a90a52012", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27062": Entry("Bubble Blobby", .regl, "21a5ea9d250242594b0dfe72e0640bfd3dfeeec8fdd5eb62aa2f777199bde5ff", authoredPixelDensity: 1),
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27093": Entry("Sigils", .p5js100, "40cecbb4554fce586577a2e111b18d8d92566a5cff56ae0d85043f51b921c47c", authoredPixelDensity: 2, maximumLogicalDimension: 2000),
        "0xaa00b2b2db36b8f8004a9aa96f0012005d92b3000": Entry("pool party", .p5js190, "07975b0bf147dbff9b45e084bedb50c9f21895bb58884beeac10d0426a7d061f"),
        "0xab0000000000aa06f89b268d604a9c1c41524ac6499": Entry("Box Light Studies", .p5js100, "12ac88782ef299080819436e0b60b9f3bbdc114a96ebed92be38c45ab3aabca4", authoredPixelDensity: 2),
        "0xaf40b66072fe00cacf5a25cd1b7f1688cde20f2f1": Entry("Fold", .js, "12cf1948c430f226749cf5f44ebfdb1e61b6e0acebf0daabf1e8cc9b8cc159ab", authoredPixelDensity: 2),
        "0xb3526a6400260078517643cfd8490078803e00000": Entry("Chroma Genesis", .p5js190, "95e0d6434c5e0cd050f5ac1c9b54fb8455e41dbe3e4a257f6758036ddf50dbab", authoredPixelDensity: 2),
        "0xd40030fd1d00f1a9944462ff0025e9c8d00035000": Entry("Pax", .js, "c8bc8860f18590ea009fb5ddf1f0c205ce6a49c9088b7744c55e3f61764fa111", authoredPixelDensity: 1),
        "0x0000000fae63d15270aafe9e08a71cd28079572d1": Entry("Echoes Of Frida: Sutura", .p5js100, "3d5a91561b19b1411a59baf91df5e729a64a313bb91ac45c59a078cd1bea5f3a", authoredPixelDensity: 2),
        "0x47a91457a3a1f700097199fd63c039c4784384ab12": Entry("Pig's Tail", .p5js100, "8d145248a020c4902e1d18b20618d115d11e2f2c379a584bce68e50453afa872", authoredPixelDensity: 2),
        "0x47a91457a3a1f700097199fd63c039c4784384ab290": Entry("And Yet We Love", .p5js100, "5d109a0f77fbd841085fcff1cb17e25324165df506f73adf880563fa5ca3cb94", authoredPixelDensity: 2),
        "0x47a91457a3a1f700097199fd63c039c4784384ab3": Entry("Afterimage", .js, "e599fa9ce386cc508dba531d4fd906091a9800f654dcef62f1c49d3ba3ef452f", authoredPixelDensity: 1),
        "0x47a91457a3a1f700097199fd63c039c4784384ab315": Entry("Can you see it", .p5js100, "bc07c9b1cb6acfb676896dee34f3cd4796f5b6d7011c832707905cdc95ba7e50"),
        "0x47a91457a3a1f700097199fd63c039c4784384ab5": Entry("Melt Into You", .p5js100, "decd994eee67db355b4695b78b9a52f5cfc7c7fae3fa1b9e8aae998ca707f930", authoredPixelDensity: 1),
        "0x47a91457a3a1f700097199fd63c039c4784384ab82": Entry("Delights", .js, "fcaa09f23fac65a67593b9d4418e59131e17aaa2a7b06dda9230c4c1a10c8d69", authoredPixelDensity: 1),
    ]
}
