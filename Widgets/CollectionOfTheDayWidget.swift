// ∅ 2026 lil org

import AppIntents
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
    case defaultSelectedCollection
    case fixedCollection(id: String)

    func collection(for date: Date) -> WidgetCollection? {
        switch self {
        case .collectionOfTheDay:
            return CollectionOfTheDayWidgetData.collection(for: date)
        case .defaultSelectedCollection:
            return CollectionOfTheDayWidgetData.defaultSelectedCollection(for: date)
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
        CollectionWidgetTimelineFactory.placeholderEntry(source: source)
    }

    func getSnapshot(in context: Context, completion: @escaping (CollectionOfTheDayEntry) -> Void) {
        completion(CollectionWidgetTimelineFactory.placeholderEntry(source: source))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CollectionOfTheDayEntry>) -> Void) {
        CollectionWidgetTimelineFactory.timeline(source: source, context: context, completion: completion)
    }
}

private enum CollectionWidgetTimelineFactory {
    static func placeholderEntry(source: CollectionOfTheDaySource, date: Date = Date()) -> CollectionOfTheDayEntry {
        fallbackEntry(source: source, date: date)
    }

    static func timeline(
        source: CollectionOfTheDaySource,
        context: TimelineProviderContext,
        date: Date = Date(),
        completion: @escaping (Timeline<CollectionOfTheDayEntry>) -> Void
    ) {
        guard let collection = source.collection(for: date) else {
            completion(Timeline(
                entries: [emptyEntry(date: date)],
                policy: .after(CollectionOfTheDayWidgetData.retryDate(after: date))
            ))
            return
        }

        guard let imageReference = CollectionOfTheDayWidgetData.randomStaticImageReference(collection: collection) else {
            completion(fallbackTimeline(collection: collection, date: date))
            return
        }

        let maxPixelSize = CollectionOfTheDayWidgetData.maxImagePixelSize(displaySize: context.displaySize)
        let request = URLRequest(url: imageReference.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  isSuccessfulImageResponse(response),
                  let imageData = CollectionOfTheDayWidgetData.preparedWidgetImageData(
                    data,
                    maxPixelSize: maxPixelSize
                  ),
                  let image = CollectionOfTheDayWidgetData.platformImage(data: imageData) else {
                completion(fallbackTimeline(collection: collection, date: date))
                return
            }

            let entry = CollectionOfTheDayEntry(
                date: date,
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
            completion(Timeline(entries: [entry], policy: .after(CollectionOfTheDayWidgetData.nextRotationDate(after: date))))
        }.resume()
    }

    static func timeline(
        source: CollectionOfTheDaySource,
        context: TimelineProviderContext,
        date: Date = Date()
    ) async -> Timeline<CollectionOfTheDayEntry> {
        await withCheckedContinuation { continuation in
            timeline(source: source, context: context, date: date) { timeline in
                continuation.resume(returning: timeline)
            }
        }
    }

    private static func fallbackTimeline(collection: WidgetCollection, date: Date) -> Timeline<CollectionOfTheDayEntry> {
        Timeline(
            entries: [fallbackEntry(collection: collection, date: date)],
            policy: .after(CollectionOfTheDayWidgetData.retryDate(after: date))
        )
    }

    private static func fallbackEntry(source: CollectionOfTheDaySource, date: Date) -> CollectionOfTheDayEntry {
        guard let collection = source.collection(for: date) else {
            return emptyEntry(date: date)
        }

        return fallbackEntry(collection: collection, date: date)
    }

    private static func emptyEntry(date: Date) -> CollectionOfTheDayEntry {
        return CollectionOfTheDayEntry(
            date: date,
            collectionId: "",
            tokenId: nil,
            coverAssetName: "",
            image: nil
        )
    }

    private static func fallbackEntry(collection: WidgetCollection, date: Date) -> CollectionOfTheDayEntry {
        let cachedImage = CollectionOfTheDayWidgetData.cachedImage(collectionId: collection.id)
        return CollectionOfTheDayEntry(
            date: date,
            collectionId: collection.id,
            tokenId: cachedImage == nil ? nil : CollectionOfTheDayWidgetData.cachedTokenId(collectionId: collection.id),
            coverAssetName: collection.coverAssetName,
            image: cachedImage
        )
    }

    private static func isSuccessfulImageResponse(_ response: URLResponse?) -> Bool {
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
#if canImport(UIKit)
        Image(uiImage: image)
#elseif canImport(AppKit)
        Image(nsImage: image)
#endif
    }
}

struct WidgetCollectionEntity: AppEntity {
    static let defaultQuery = WidgetCollectionEntityQuery()
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Collection")

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(collection: WidgetCollection) {
        id = collection.id
        name = collection.name
    }
}

struct WidgetCollectionEntityQuery: EntityQuery, EnumerableEntityQuery {
    init() {}

    func entities(for identifiers: [WidgetCollectionEntity.ID]) async throws -> [WidgetCollectionEntity] {
        identifiers.compactMap { identifier in
            CollectionOfTheDayWidgetData.collection(id: identifier).map(WidgetCollectionEntity.init(collection:))
        }
    }

    func allEntities() async throws -> [WidgetCollectionEntity] {
        CollectionOfTheDayWidgetData.configurationCollections().map(WidgetCollectionEntity.init(collection:))
    }

    func defaultResult() async -> WidgetCollectionEntity? {
        CollectionOfTheDayWidgetData.defaultSelectedCollection().map(WidgetCollectionEntity.init(collection:))
    }
}

struct SelectedCollectionWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Collection"
    static let description = IntentDescription("Choose a collection to display.")

    @Parameter(title: "Collection")
    var collection: WidgetCollectionEntity?
}

struct SelectedCollectionWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CollectionOfTheDayEntry {
        CollectionWidgetTimelineFactory.placeholderEntry(source: .defaultSelectedCollection)
    }

    func snapshot(for configuration: SelectedCollectionWidgetIntent, in context: Context) async -> CollectionOfTheDayEntry {
        CollectionWidgetTimelineFactory.placeholderEntry(source: source(for: configuration))
    }

    func timeline(for configuration: SelectedCollectionWidgetIntent, in context: Context) async -> Timeline<CollectionOfTheDayEntry> {
        await CollectionWidgetTimelineFactory.timeline(source: source(for: configuration), context: context)
    }

    private func source(for configuration: SelectedCollectionWidgetIntent) -> CollectionOfTheDaySource {
        guard let collectionId = configuration.collection?.id,
              CollectionOfTheDayWidgetData.collection(id: collectionId) != nil else {
            return .defaultSelectedCollection
        }
        return .fixedCollection(id: collectionId)
    }
}

@main
struct NftFolderWidgets: WidgetBundle {
    var body: some Widget {
        CollectionOfTheDayWidget()
        TojibaCPUCorpWidget()
        SelectedCollectionWidget()
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

struct SelectedCollectionWidget: Widget {
    let kind = "org.lil.nft-folder.selected-collection"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectedCollectionWidgetIntent.self,
            provider: SelectedCollectionWidgetProvider()
        ) { entry in
            CollectionOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Collection")
        .description("Choose a collection to display.")
#if os(visionOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLargePortrait])
#else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
#endif
        .contentMarginsDisabled()
    }
}
