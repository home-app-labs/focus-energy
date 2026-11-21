import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var source: FolderSource
    @State private var picking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let snapshot = source.snapshot {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            status(snapshot, at: context.date)
                        }
                    } else {
                        empty
                    }
                    connection
                }
                .padding(20)
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            .navigationTitle("Focus Energy")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { source.refresh() }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { source.connect(to: url) }
        }
    }

    private func status(_ snapshot: WidgetSnapshot, at date: Date) -> some View {
        VStack(spacing: 22) {
            FocusWidgetView(snapshot: snapshot, date: date, layout: .ring(230))
                .padding(.top, 8)
            FocusWidgetView(snapshot: snapshot, date: date, layout: .details)
                .padding(18)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let point = snapshot.point(at: date) {
                Text(point.advice).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            week(snapshot)
        }
    }

    private func week(_ snapshot: WidgetSnapshot) -> some View {
        VStack(spacing: 10) {
            Text("This week").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(snapshot.week) { day in
                    VStack(spacing: 5) {
                        Text(day.label).font(.caption2.weight(.semibold))
                        Text(day.isFuture ? "·" : day.emoji).font(.title3).frame(height: 28)
                        Text(day.coins > 0 ? CompactStatus.short(day.coins) : "–")
                            .font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(day.isToday ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 10))
                    .opacity(day.isFuture ? 0.45 : 1)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer").font(.system(size: 54)).foregroundStyle(.secondary)
            Text("No timer data yet").font(.title3.weight(.semibold))
            Text("Focus Energy on your Mac keeps its timer in iCloud Drive. Choose that folder below to follow it here.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    private var connection: some View {
        VStack(spacing: 10) {
            if let name = source.folderName {
                Label("Following \"\(name)\" in iCloud Drive", systemImage: "icloud.fill")
                    .font(.footnote).foregroundStyle(.secondary)
                if let updated = source.snapshot?.updatedAt {
                    Text("Mac updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            if let problem = source.problem {
                Text(problem).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            Button { picking = true } label: {
                Label(source.isConnected ? "Choose a different folder" : "Choose the Focus Energy folder",
                      systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.25, green: 0.48, blue: 1.0))
        }
        .padding(.top, 6)
    }
}
