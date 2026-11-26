//
//  TitleWidgets.swift
//  Title Capitalizr Widgets (iOS, macOS)
//
//  Recent Titles: your latest favourite or copied titles (tap one to reopen it).
//  Quick Convert: opens the app on a style guide, ready to paste.
//

import SwiftUI
import TitleCaseKit
import WidgetKit

struct TitlesEntry: TimelineEntry {
    let date: Date
    let items: [HistoryEntry]
    let guide: StyleGuide
}

struct TitlesProvider: TimelineProvider {
    static let sample = [
        HistoryEntry(input: "the lord of the rings", output: "The Lord of the Rings", guide: .mla, favorite: true),
        HistoryEntry(input: "a war between the worlds", output: "A War Between the Worlds", guide: .apa),
        HistoryEntry(input: "how to log in to your account", output: "How to Log In to Your Account", guide: .chicago),
    ]

    func placeholder(in context: Context) -> TitlesEntry { TitlesEntry(date: .now, items: Self.sample, guide: .mla) }

    func getSnapshot(in context: Context, completion: @escaping (TitlesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TitlesEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> TitlesEntry {
        let s = SharedVault.load()
        let items = s.favorites + s.recents
        return TitlesEntry(date: .now, items: Array(items.prefix(6)), guide: s.lastGuide)
    }
}

private enum W {
    static let ink = Color.black
    static let ground = Color.white
    static let blue = Color(red: 0x0F / 255, green: 0x3F / 255, blue: 0xA8 / 255)
    static let yellow = Color(red: 0xF2 / 255, green: 0xC2 / 255, blue: 0x30 / 255)
    static let red = Color(red: 0xD6 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let secondary = Color(red: 0x3C / 255, green: 0x3C / 255, blue: 0x3C / 255)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Jost", size: size).weight(weight) }

    static var stripe: some View {
        HStack(spacing: 0) {
            red.frame(width: 18)
            yellow.frame(width: 18)
            blue.frame(width: 18)
            ink
        }
        .frame(height: 5)
    }
}

struct RecentTitlesView: View {
    let entry: TitlesEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 3
        default: return 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECENT TITLES").font(W.font(11, .bold)).tracking(1.2)
                Spacer()
                Image(systemName: "textformat").font(.system(size: 12, weight: .bold))
            }
            W.stripe
            if entry.items.isEmpty {
                Text("Copy or favourite a title in Title Capitalizr and it shows up here.")
                    .font(W.font(13)).foregroundStyle(W.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(count)) { item in
                    Link(destination: TCLink.entry(item.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.output).font(W.font(family == .systemSmall ? 16 : 14, .semibold)).lineLimit(family == .systemSmall ? 4 : 2)
                            HStack(spacing: 4) {
                                if item.favorite { Image(systemName: "star.fill").font(.system(size: 9)) }
                                Text(item.guide.shortName.uppercased()).font(W.font(9, .bold)).tracking(1)
                            }
                            .foregroundStyle(W.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(W.ink)
        .widgetURL(TCLink.open(mode: "title"))
        .containerBackground(W.ground, for: .widget)
    }
}

struct RecentTitlesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentTitles", provider: TitlesProvider()) { entry in
            RecentTitlesView(entry: entry)
        }
        .configurationDisplayName("Recent Titles")
        .description("Your favourite and recently copied titles.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickConvertView: View {
    let entry: TitlesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TITLE").font(W.font(22, .bold)).tracking(1)
            Text("CAPITALIZR").font(W.font(16, .bold)).tracking(1).foregroundStyle(W.blue)
                .lineLimit(1).minimumScaleFactor(0.6)
            W.stripe
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 14, weight: .bold))
                Text("PASTE IN \(entry.guide.shortName.uppercased())").font(W.font(11, .bold)).tracking(0.8)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .foregroundStyle(W.ground)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(W.ink)
        }
        .foregroundStyle(W.ink)
        .widgetURL(TCLink.open(guide: entry.guide, mode: "paste"))
        .containerBackground(W.ground, for: .widget)
    }
}

struct QuickConvertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickConvert", provider: TitlesProvider()) { entry in
            QuickConvertView(entry: entry)
        }
        .configurationDisplayName("Quick Convert")
        .description("Opens Title Capitalizr on your style guide and converts what you copied.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct TitleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecentTitlesWidget()
        QuickConvertWidget()
    }
}
