// ∅ 2026 lil org

import AppIntents
import SwiftUI
import WidgetKit

nonisolated struct CollectionOfTheDayEntry: TimelineEntry, Sendable {
    let date: Date
    let collectionId: String
    let tokenId: String?
    let coverAssetName: String
    let imageData: Data?

    var widgetURL: URL? {
        guard !collectionId.isEmpty else { return nil }
        return WidgetDeepLink.collection(id: collectionId, tokenId: tokenId).url
    }
}

nonisolated enum CollectionOfTheDaySource: Sendable {
    case collectionOfTheDay
    case defaultSelectedCollection
    case fixedCollection(id: String)

    func collection(for date: Date) -> WidgetCollection? {
        switch self {
        case .collectionOfTheDay:
            return CollectionOfTheDayWidgetData.collection(for: date)
        case .defaultSelectedCollection:
            return CollectionOfTheDayWidgetData.defaultSelectedCollection()
        case let .fixedCollection(id):
            return CollectionOfTheDayWidgetData.collection(id: id)
        }
    }
}

nonisolated struct CollectionOfTheDayProvider: TimelineProvider, Sendable {
    let source: CollectionOfTheDaySource

    init(source: CollectionOfTheDaySource = .collectionOfTheDay) {
        self.source = source
    }

    func placeholder(in context: Context) -> CollectionOfTheDayEntry {
        CollectionWidgetTimelineFactory.placeholderEntry(source: source)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CollectionOfTheDayEntry) -> Void) {
        completion(CollectionWidgetTimelineFactory.placeholderEntry(source: source))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<CollectionOfTheDayEntry>) -> Void
    ) {
        let displaySize = context.displaySize
        Task {
            completion(await CollectionWidgetTimelineFactory.timeline(source: source, displaySize: displaySize))
        }
    }
}

nonisolated private enum CollectionWidgetTimelineFactory {
    static func placeholderEntry(source: CollectionOfTheDaySource, date: Date = Date()) -> CollectionOfTheDayEntry {
        fallbackEntry(source: source, date: date)
    }

    static func timeline(
        source: CollectionOfTheDaySource,
        displaySize: CGSize,
        date: Date = Date(),
        rotationFrequency: WidgetRotationFrequency? = nil
    ) async -> Timeline<CollectionOfTheDayEntry> {
        guard let collection = source.collection(for: date) else {
            return Timeline(
                entries: [emptyEntry(date: date)],
                policy: .after(CollectionOfTheDayWidgetData.retryDate(after: date))
            )
        }

        guard let imageReference = CollectionOfTheDayWidgetData.randomStaticImageReference(collection: collection) else {
            return fallbackTimeline(collection: collection, date: date)
        }

        let maxPixelSize = CollectionOfTheDayWidgetData.maxImagePixelSize(displaySize: displaySize)
        let request = URLRequest(
            url: imageReference.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard isSuccessfulImageResponse(response),
                  let imageData = await CollectionOfTheDayWidgetData.preparedWidgetImageData(
                    data,
                    maxPixelSize: maxPixelSize
                  ) else {
                return fallbackTimeline(collection: collection, date: date)
            }

            await CollectionOfTheDayWidgetData.cacheImageData(
                imageData,
                collectionId: collection.id,
                tokenId: imageReference.tokenId
            )
            let entry = CollectionOfTheDayEntry(
                date: date,
                collectionId: collection.id,
                tokenId: imageReference.tokenId,
                coverAssetName: collection.coverAssetName,
                imageData: imageData
            )
            let nextRotationDate: Date
            if let rotationFrequency {
                nextRotationDate = CollectionOfTheDayWidgetData.nextRotationDate(
                    after: date,
                    frequency: rotationFrequency
                )
            } else {
                nextRotationDate = CollectionOfTheDayWidgetData.nextRotationDate(after: date)
            }
            return Timeline(entries: [entry], policy: .after(nextRotationDate))
        } catch {
            return fallbackTimeline(collection: collection, date: date)
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
            imageData: nil
        )
    }

    private static func fallbackEntry(collection: WidgetCollection, date: Date) -> CollectionOfTheDayEntry {
        let cachedImage = CollectionOfTheDayWidgetData.cachedImage(collectionId: collection.id)
        return CollectionOfTheDayEntry(
            date: date,
            collectionId: collection.id,
            tokenId: cachedImage?.tokenId,
            coverAssetName: collection.coverAssetName,
            imageData: cachedImage?.data
        )
    }

    private static func isSuccessfulImageResponse(_ response: URLResponse?) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(httpResponse.statusCode)
    }
}

@MainActor
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
        if let imageData = entry.imageData,
           let image = CollectionOfTheDayWidgetData.platformImage(data: imageData) {
            fullColorWidgetImage(platformImage(image))
        } else if !entry.coverAssetName.isEmpty {
            fullColorWidgetImage(Image(entry.coverAssetName))
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private func fullColorWidgetImage(_ image: Image) -> some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 26.0, *) {
            image
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
        } else {
            image
                .resizable()
                .scaledToFill()
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

nonisolated struct WidgetCollectionEntity: AppEntity, Sendable {
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

nonisolated struct WidgetCollectionEntityQuery: EntityQuery, EnumerableEntityQuery, Sendable {
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

nonisolated enum WidgetRotationFrequency: String, AppEnum, CaseIterable, Sendable {
    case onceDaily
    case twiceDaily
    case threeTimesDaily

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rotation")
    static let caseDisplayRepresentations: [WidgetRotationFrequency: DisplayRepresentation] = [
        .onceDaily: "Once per Day",
        .twiceDaily: "Twice per Day",
        .threeTimesDaily: "Three Times per Day",
    ]

    var rotationHours: [Int] {
        switch self {
        case .onceDaily:
            return [8]
        case .twiceDaily:
            return [8, 20]
        case .threeTimesDaily:
            return [8, 14, 20]
        }
    }

    var fallbackHourInterval: Int {
        switch self {
        case .onceDaily:
            return 24
        case .twiceDaily:
            return 12
        case .threeTimesDaily:
            return 8
        }
    }
}

struct SelectedCollectionWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Collection"
    static let description = IntentDescription("Choose a collection to display.")

    @Parameter(title: "Collection")
    var collection: WidgetCollectionEntity?

    @Parameter(title: "Rotation", default: .twiceDaily)
    var rotation: WidgetRotationFrequency
}

nonisolated struct SelectedCollectionWidgetProvider: AppIntentTimelineProvider, Sendable {
    func placeholder(in context: Context) -> CollectionOfTheDayEntry {
        CollectionWidgetTimelineFactory.placeholderEntry(source: .defaultSelectedCollection)
    }

    func snapshot(for configuration: SelectedCollectionWidgetIntent, in context: Context) async -> CollectionOfTheDayEntry {
        CollectionWidgetTimelineFactory.placeholderEntry(source: source(for: configuration))
    }

    func timeline(for configuration: SelectedCollectionWidgetIntent, in context: Context) async -> Timeline<CollectionOfTheDayEntry> {
        await CollectionWidgetTimelineFactory.timeline(
            source: source(for: configuration),
            displaySize: context.displaySize,
            rotationFrequency: configuration.rotation
        )
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
struct NftPlayerWidgets: WidgetBundle {
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
