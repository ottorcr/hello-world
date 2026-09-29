import AppIntents
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

// Must match lib/widget_sync.dart and the App Group on both targets.
private let appGroupId = "group.com.ottorcr.randomThoughts"
private let feedKey = "feed_json"

private let emptyText = "No thoughts yet. Open the app to sign in and add friends."

// MARK: - Data

/// One post, as cached on this device by the app. The widget never uses the
/// network; the app refreshes this copy with the user's own sign-in.
struct FeedItem: Decodable {
  let author: String
  let text: String
  let imagePath: String?

  enum CodingKeys: String, CodingKey {
    case author = "a"
    case text = "t"
    case imagePath = "i"
  }
}

enum FeedStore {
  static func load() -> [FeedItem] {
    guard let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: feedKey),
          let data = raw.data(using: .utf8),
          let items = try? JSONDecoder().decode([FeedItem].self, from: data)
    else { return [] }
    return items
  }

  /// Loads a downscaled photo so the widget stays within its memory limit.
  static func thumbnail(at path: String?, maxPixels: Int = 700) -> UIImage? {
    guard let path, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: cg)
  }
}

// MARK: - Timeline

struct ThoughtEntry: TimelineEntry {
  let date: Date
  let author: String?
  let text: String
  let photo: UIImage?

  static func random(from items: [FeedItem], at date: Date) -> ThoughtEntry {
    guard let item = items.randomElement() else {
      return ThoughtEntry(date: date, author: nil, text: emptyText, photo: nil)
    }
    return ThoughtEntry(
      date: date, author: item.author, text: item.text,
      photo: FeedStore.thumbnail(at: item.imagePath))
  }
}

struct ThoughtsProvider: TimelineProvider {
  func placeholder(in context: Context) -> ThoughtEntry {
    ThoughtEntry(date: .now, author: "A friend", text: "Shower thoughts, delivered.", photo: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (ThoughtEntry) -> Void) {
    completion(.random(from: FeedStore.load(), at: .now))
  }

  /// A different random thought every 30 minutes, from the on-device copy.
  func getTimeline(in context: Context, completion: @escaping (Timeline<ThoughtEntry>) -> Void) {
    let items = FeedStore.load()
    let now = Date()
    let entries = (0..<6).map { i in
      ThoughtEntry.random(from: items, at: now.addingTimeInterval(Double(i) * 30 * 60))
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

// MARK: - Shuffle button

/// Tapping "Shuffle" runs this. WidgetKit then reloads the timeline, which
/// picks another random thought.
struct ShuffleThoughtIntent: AppIntent {
  static var title: LocalizedStringResource = "Shuffle thought"

  func perform() async throws -> some IntentResult {
    .result()
  }
}

// MARK: - Views

struct ThoughtsWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ThoughtEntry

  var body: some View {
    switch family {
    case .accessoryRectangular:
      VStack(alignment: .leading) {
        if let author = entry.author {
          Text(author).font(.caption2).foregroundStyle(.secondary)
        }
        Text(entry.text.isEmpty ? "📷 Photo" : entry.text)
          .font(.headline)
          .minimumScaleFactor(0.6)
      }
    default:
      VStack(alignment: .leading, spacing: 6) {
        Text(entry.author.map { "💭 from \($0)" } ?? "💭 Random Thoughts")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let photo = entry.photo {
          Color.clear
            .overlay(Image(uiImage: photo).resizable().scaledToFill())
            .clipShape(RoundedRectangle(cornerRadius: 12))
          if !entry.text.isEmpty {
            Text(entry.text).font(.caption).fontWeight(.semibold).lineLimit(2)
          }
        } else {
          Text(entry.text)
            .font(.system(family == .systemSmall ? .callout : .title3, design: .rounded))
            .fontWeight(.semibold)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        HStack {
          Spacer()
          Button(intent: ShuffleThoughtIntent()) {
            Label("Shuffle", systemImage: "shuffle").font(.caption)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.tint)
        }
      }
    }
  }
}

struct ThoughtsWidget: Widget {
  // Must match WidgetSync.iOSWidgetKind in lib/widget_sync.dart.
  let kind = "ThoughtsWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ThoughtsProvider()) { entry in
      ThoughtsWidgetView(entry: entry)
        .tint(Color(red: 0.42, green: 0.25, blue: 0.88))
        .containerBackground(for: .widget) {
          LinearGradient(
            colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        }
    }
    .configurationDisplayName("Random Thoughts")
    .description("A random thought from one of your friends.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
  }
}

#Preview(as: .systemMedium) {
  ThoughtsWidget()
} timeline: {
  ThoughtEntry(date: .now, author: "Sam", text: "What if pigeons are just rats that learned to fly?", photo: nil)
  ThoughtEntry(date: .now, author: "Alex", text: "Coffee is just bean soup.", photo: nil)
}
