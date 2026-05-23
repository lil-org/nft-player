// ∅ 2026 lil org

import SwiftUI
import WidgetKit

struct CollectionOfTheDayEntry: TimelineEntry {
    let date: Date
    let collectionId: String
    let tokenId: String?
    let coverAssetName: String
    let image: WidgetPlatformImage?

    var widgetURL: URL? {
        guard !collectionId.isEmpty else { return nil }
        return WidgetDeepLink.collection(id: collectionId, tokenId: tokenId).url
    }
}

enum CollectionOfTheDaySource {
    case collectionOfTheDay
    case fixedCollection(id: String)

    func collection(for date: Date) -> WidgetCollection? {
        switch self {
        case .collectionOfTheDay:
            return CollectionOfTheDayWidgetData.collection(for: date)
        case let .fixedCollection(id):
            return CollectionOfTheDayWidgetData.collection(id: id)
        }
    }
}

struct CollectionOfTheDayProvider: TimelineProvider {
    let source: CollectionOfTheDaySource

    init(source: CollectionOfTheDaySource = .collectionOfTheDay) {
        self.source = source
    }

    func placeholder(in context: Context) -> CollectionOfTheDayEntry {
        fallbackEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CollectionOfTheDayEntry) -> Void) {
        completion(fallbackEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CollectionOfTheDayEntry>) -> Void) {
        let now = Date()
        guard let collection = source.collection(for: now) else {
            completion(Timeline(entries: [fallbackEntry(date: now)], policy: .after(CollectionOfTheDayWidgetData.retryDate(after: now))))
            return
        }

        guard let imageReference = CollectionOfTheDayWidgetData.randomStaticImageReference(collection: collection) else {
            completion(fallbackTimeline(collection: collection, date: now))
            return
        }

        let request = URLRequest(url: imageReference.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  isSuccessfulImageResponse(response),
                  let imageData = CollectionOfTheDayWidgetData.preparedWidgetImageData(
                    data,
                    maxPixelSize: CollectionOfTheDayWidgetData.maxImagePixelSize(displaySize: context.displaySize)
                  ),
                  let image = CollectionOfTheDayWidgetData.platformImage(data: imageData) else {
                completion(fallbackTimeline(collection: collection, date: now))
                return
            }

            let entry = CollectionOfTheDayEntry(
                date: now,
                collectionId: collection.id,
                tokenId: imageReference.tokenId,
                coverAssetName: collection.coverAssetName,
                image: image
            )
            CollectionOfTheDayWidgetData.cacheImageData(
                imageData,
                collectionId: collection.id,
                tokenId: imageReference.tokenId
            )
            completion(Timeline(entries: [entry], policy: .after(CollectionOfTheDayWidgetData.nextRotationDate(after: now))))
        }.resume()
    }

    private func fallbackTimeline(collection: WidgetCollection, date: Date) -> Timeline<CollectionOfTheDayEntry> {
        Timeline(
            entries: [fallbackEntry(collection: collection, date: date)],
            policy: .after(CollectionOfTheDayWidgetData.retryDate(after: date))
        )
    }

    private func fallbackEntry(date: Date) -> CollectionOfTheDayEntry {
        if let collection = source.collection(for: date) {
            return fallbackEntry(collection: collection, date: date)
        }

        return CollectionOfTheDayEntry(
            date: date,
            collectionId: "",
            tokenId: nil,
            coverAssetName: "",
            image: nil
        )
    }

    private func fallbackEntry(collection: WidgetCollection, date: Date) -> CollectionOfTheDayEntry {
        let cachedImage = CollectionOfTheDayWidgetData.cachedImage(collectionId: collection.id)
        return CollectionOfTheDayEntry(
            date: date,
            collectionId: collection.id,
            tokenId: cachedImage == nil ? nil : CollectionOfTheDayWidgetData.cachedTokenId(collectionId: collection.id),
            coverAssetName: collection.coverAssetName,
            image: cachedImage
        )
    }

    private func isSuccessfulImageResponse(_ response: URLResponse?) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(httpResponse.statusCode)
    }
}

struct CollectionOfTheDayWidgetView: View {
    let entry: CollectionOfTheDayEntry

    var body: some View {
        GeometryReader { geometry in
            widgetImage
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .containerBackground(.black, for: .widget)
        .widgetURL(entry.widgetURL)
    }

    @ViewBuilder
    private var widgetImage: some View {
        if let image = entry.image {
            platformImage(image)
                .resizable()
                .scaledToFill()
        } else if !entry.coverAssetName.isEmpty {
            Image(entry.coverAssetName)
                .resizable()
                .scaledToFill()
        } else {
            Color.black
        }
    }

    private func platformImage(_ image: WidgetPlatformImage) -> Image {
#if os(iOS)
        Image(uiImage: image)
#elseif os(macOS)
        Image(nsImage: image)
#endif
    }
}

@main
struct NftFolderWidgets: WidgetBundle {
    var body: some Widget {
        CollectionOfTheDayWidget()
        TojibaCPUCorpWidget()
    }
}

struct CollectionOfTheDayWidget: Widget {
    let kind = "org.lil.nft-folder.collection-of-the-day"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CollectionOfTheDayProvider()) { entry in
            CollectionOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Collection of the Day")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TojibaCPUCorpWidget: Widget {
    let kind = "org.lil.nft-folder.tojiba-cpu-corp"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: CollectionOfTheDayProvider(
                source: .fixedCollection(id: CollectionOfTheDayWidgetData.tojibaCPUCorpCollectionId)
            )
        ) { entry in
            CollectionOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Tojiba CPU Corp")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}
