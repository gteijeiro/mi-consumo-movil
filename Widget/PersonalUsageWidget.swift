import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .initial)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, snapshot: SnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: .now, snapshot: SnapshotStore().load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(SharedSettings.refreshInterval))))
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry
    private let blue = Color(red: 0.04, green: 0.34, blue: 0.68)

    var body: some View {
        Group {
            if family == .systemMedium { mediumLayout } else { smallLayout }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.snapshot.state == .needsLogin ? SharedSettings.loginURL : SharedSettings.appURL)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Mi Consumo Móvil", systemImage: "cellularbars")
                .font(.caption.bold()).foregroundStyle(blue)
            Spacer(minLength: 0)
            Text(entry.snapshot.remainingDisplay ?? "—")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65).lineLimit(1)
            Text("disponibles").font(.caption).foregroundStyle(.secondary)
            usageProgress
            if entry.snapshot.state == .needsLogin {
                Text("Sesión vencida · abrir login →")
                    .font(.caption2).lineLimit(1).foregroundStyle(.orange)
            } else if let pack = entry.snapshot.packs.first {
                Text("Próximo vencimiento: \(PackDateFormat.day(pack.expiresAt))")
                    .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            } else {
                Text(entry.snapshot.state == .needsLogin ? "Abrir login →" : entry.snapshot.message)
                    .font(.caption2).lineLimit(2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Mi Consumo Móvil", systemImage: "cellularbars")
                    .font(.caption.bold()).foregroundStyle(blue)
                Spacer(minLength: 0)
                Text(entry.snapshot.remainingDisplay ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("disponibles").font(.caption).foregroundStyle(.secondary)
                usageProgress
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.quaternary).frame(width: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot.state == .needsLogin ? "ÚLTIMA LECTURA · LOGIN" : "VENCIMIENTOS").font(.caption2.bold())
                    .tracking(0.7).foregroundStyle(.secondary)
                if entry.snapshot.packs.isEmpty {
                    Text(entry.snapshot.state == .needsLogin ? "Sesión vencida · Abrir login →" : entry.snapshot.message)
                        .font(.caption)
                } else {
                    ForEach(entry.snapshot.packs.prefix(3)) { pack in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(pack.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(pack.remainingDisplay).bold()
                            }
                            .font(.caption2)
                            Text("Vence \(PackDateFormat.short(pack.expiresAt))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let updated = entry.snapshot.updatedAt {
                    Text("Actualizado \(updated.formatted(.dateTime.hour().minute()))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    @ViewBuilder
    private var usageProgress: some View {
        if let used = entry.snapshot.usedGB, let total = entry.snapshot.totalGB {
            ProgressView(value: min(max(used / max(total, 0.01), 0), 1)).tint(blue)
        }
    }
}

@main
struct PersonalUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedSettings.widgetKind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Mi Consumo Móvil")
        .description("Muestra los gigas disponibles y el vencimiento de cada pack.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
