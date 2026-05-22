// ∅ 2026 lil org

import SwiftUI
import WidgetKit

struct CollectionOfTheDayEntry: TimelineEntry {
    let date: Date
    let collectionId: String
    let coverAssetName: String
    let image: WidgetPlatformImage?

    var widgetURL: URL? {
        guard !collectionId.isEmpty else { return nil }
        return WidgetDeepLink.collection(id: collectionId).url
    }
}

struct CollectionOfTheDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> CollectionOfTheDayEntry {
        fallbackEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CollectionOfTheDayEntry) -> Void) {
        completion(fallbackEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CollectionOfTheDayEntry>) -> Void) {
        let now = Date()
        guard let collection = CollectionOfTheDayWidgetData.collection(for: now) else {
            completion(Timeline(entries: [fallbackEntry(date: now)], policy: .after(CollectionOfTheDayWidgetData.retryDate(after: now))))
            return
        }

        guard let imageURL = CollectionOfTheDayWidgetData.randomStaticImageURL(collection: collection) else {
            completion(fallbackTimeline(collection: collection, date: now))
            return
        }

        let request = URLRequest(url: imageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
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

            CollectionOfTheDayWidgetData.cacheImageData(imageData, collectionId: collection.id)
            let entry = CollectionOfTheDayEntry(
                date: now,
                collectionId: collection.id,
                coverAssetName: collection.coverAssetName,
                image: image
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
        if let collection = CollectionOfTheDayWidgetData.collection(for: date) {
            return fallbackEntry(collection: collection, date: date)
        }

        return CollectionOfTheDayEntry(
            date: date,
            collectionId: "",
            coverAssetName: "",
            image: nil
        )
    }

    private func fallbackEntry(collection: WidgetCollection, date: Date) -> CollectionOfTheDayEntry {
        CollectionOfTheDayEntry(
            date: date,
            collectionId: collection.id,
            coverAssetName: collection.coverAssetName,
            image: CollectionOfTheDayWidgetData.cachedImage(collectionId: collection.id)
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
struct CollectionOfTheDayWidget: Widget {
    let kind = "org.lil.nft-folder.collection-of-the-day"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CollectionOfTheDayProvider()) { entry in
            CollectionOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Collection of the Day")
        .description("A daily collection from Nft Folder.")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}
