import SwiftUI
import MapKit

struct DayReplayView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let date: Date
    @State private var camera: MapCameraPosition = .automatic
    @State private var index = 0
    @State private var playing = false
    private var entries: [JournalEntry] { store.entries(in: TimeMath.day(date)) }
    private var current: JournalEntry? { entries.indices.contains(index) ? entries[index] : nil }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                Map(position: $camera) {
                    ForEach(store.places.filter { place in entries.contains { $0.placeID == place.id || $0.destinationID == place.id } }) { place in
                        Annotation(place.name, coordinate: place.coordinate) {
                            PlaceBadge(kind: place.kind).padding(6).background(Theme.surface, in: Circle())
                                .overlay(Circle().stroke(current?.placeID == place.id ? Theme.accent : .clear, lineWidth: 3))
                        }
                    }
                    if let current, current.kind == .travel,
                       let from = store.place(current.placeID), let to = store.place(current.destinationID) {
                        MapPolyline(coordinates: [from.coordinate, to.coordinate])
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    }
                }.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 28))
                Text("按记录顺序回看地点。虚线仅连接起终点，不代表实际行走路线。").font(.footnote).foregroundStyle(.secondary)
                if let current {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.title(current)).font(.title2.bold())
                            Text("\(current.start.formatted(date: .omitted, time: .shortened)) · \(TimeMath.duration(current.duration(in: TimeMath.day(date))))").foregroundStyle(.secondary)
                            HStack {
                                Button("上一段", systemImage: "backward.end.fill") { index = max(0, index - 1); focus() }.disabled(index == 0)
                                Spacer()
                                Button(playing ? "暂停" : "播放", systemImage: playing ? "pause.fill" : "play.fill") {
                                    if index == entries.count - 1 { index = 0; focus() }
                                    playing.toggle()
                                }.buttonStyle(PrimaryButtonStyle())
                                Spacer()
                                Button("下一段", systemImage: "forward.end.fill") { index = min(entries.count - 1, index + 1); focus() }.disabled(index >= entries.count - 1)
                            }.labelStyle(.iconOnly).controlSize(.large)
                            Text("\(index + 1) / \(entries.count) 段").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                EntryList(interval: TimeMath.day(date))
            }.padding(20).frame(maxWidth: 760)
        }.frame(maxWidth: .infinity).pageCanvas().navigationTitle("这一天的地图").navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: focus)
            .onDisappear { playing = false }
            .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
            .task(id: playing) {
                guard playing else { return }
                while !Task.isCancelled && playing {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    guard !Task.isCancelled else { return }
                    if index + 1 < entries.count { index += 1; focus() }
                    else { playing = false }
                }
            }
    }
    private func focus() {
        guard let entry = current, let place = store.place(entry.placeID) else { return }
        withAnimation(reduceMotion ? nil : Motion.expand) {
            if entry.kind == .travel, let destination = store.place(entry.destinationID) {
                let center = CLLocationCoordinate2D(latitude: (place.latitude + destination.latitude) / 2, longitude: (place.longitude + destination.longitude) / 2)
                camera = .region(.init(center: center, span: .init(latitudeDelta: max(0.015, abs(place.latitude - destination.latitude) * 1.8), longitudeDelta: max(0.015, abs(place.longitude - destination.longitude) * 1.8))))
            } else {
                camera = .region(.init(center: place.coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600))
            }
        }
    }
}
