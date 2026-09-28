import AppIntents
import SwiftUI
import WidgetKit

// Must match lib/widget_sync.dart and the App Group on both targets.
private let appGroupId = "group.com.ottorcr.randomThoughts"
private let thoughtsKey = "thoughts_json"
private let projectIdKey = "firebase_project_id"

private let emptyText = "No thoughts yet. Open the app once to load them."

// MARK: - Data

/// Thoughts cached by the Flutter app, refreshed from Firestore's REST API.
enum ThoughtStore {
  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }

  static func cached() -> [String] {
    guard let raw = defaults?.string(forKey: thoughtsKey),
          let data = raw.data(using: .utf8),
          let list = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return list.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  static func save(_ thoughts: [String]) {
    guard let data = try? JSONEncoder().encode(thoughts),
          let raw = String(data: data, encoding: .utf8)
    else { return }
    defaults?.set(raw, forKey: thoughtsKey)
  }

  /// Latest thoughts from Firestore, or nil if the request failed.
  static func fetchFresh() async -> [String]? {
    guard let projectId = defaults?.string(forKey: projectIdKey),
          let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)"
            + "/databases/(default)/documents/thoughts?pageSize=200&orderBy=createdAt%20desc")
    else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      let page = try JSONDecoder().decode(ListDocumentsResponse.self, from: data)
      return (page.documents ?? [])
        .compactMap { $0.fields?.text?.stringValue }
        .filter { !$0.isEmpty }
    } catch {
      return nil
    }
  }
}

/// The slice of Firestore's `documents.list` response we need.
private struct ListDocumentsResponse: Decodable {
  struct Document: Decodable {
    struct Fields: Decodable {
      struct StringValue: Decodable { let stringValue: String? }
      let text: StringValue?
    }
    let fields: Fields?
  }
  let documents: [Document]?
}

// MARK: - Timeline

struct ThoughtEntry: TimelineEntry {
  let date: Date
  let text: String
}

struct ThoughtsProvider: TimelineProvider {
  func placeholder(in context: Context) -> ThoughtEntry {
    ThoughtEntry(date: .now, text: "Shower thoughts, delivered.")
  }

  func getSnapshot(in context: Context, completion: @escaping (ThoughtEntry) -> Void) {
    completion(ThoughtEntry(date: .now, text: ThoughtStore.cached().randomElement() ?? emptyText))
  }

  /// A new random thought every 30 minutes for 3 hours, then fetch again.
  func getTimeline(in context: Context, completion: @escaping (Timeline<ThoughtEntry>) -> Void) {
    Task {
      if let fresh = await ThoughtStore.fetchFresh() {
        ThoughtStore.save(fresh)
      }
      let thoughts = ThoughtStore.cached()
      let now = Date()
      let entries = (0..<6).map { i in
        ThoughtEntry(
          date: now.addingTimeInterval(Double(i) * 30 * 60),
          text: thoughts.randomElement() ?? emptyText
        )
      }
      completion(Timeline(entries: entries, policy: .atEnd))
    }
  }
}

// MARK: - Shuffle button

/// Tapping "Shuffle" runs this, and WidgetKit then reloads the timeline,
/// which picks a new random thought.
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
      Text(entry.text)
        .font(.headline)
        .minimumScaleFactor(0.6)
    default:
      VStack(alignment: .leading, spacing: 6) {
        Text("💭 Random Thoughts")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(entry.text)
          .font(.system(family == .systemSmall ? .callout : .title3, design: .rounded))
          .fontWeight(.semibold)
          .minimumScaleFactor(0.5)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .contentTransition(.opacity)
        HStack {
          Spacer()
          Button(intent: ShuffleThoughtIntent()) {
            Label("Shuffle", systemImage: "shuffle")
              .font(.caption)
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
    .description("A random thought from your friend, right on your home screen.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

#Preview(as: .systemMedium) {
  ThoughtsWidget()
} timeline: {
  ThoughtEntry(date: .now, text: "What if pigeons are just rats that learned to fly?")
  ThoughtEntry(date: .now, text: "Coffee is just bean soup.")
}
