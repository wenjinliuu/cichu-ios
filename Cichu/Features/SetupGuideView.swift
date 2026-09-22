import SwiftUI
import UIKit

struct SetupGuideView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var finish: (() -> Void)? = nil
    @State private var adding = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(eyebrow: "按自己的节奏开始", title: "让时间，有处安放。")
                    step("1", "添加一个熟悉的地方", detail: "先从家或公司开始，地图选点后设定识别范围。", done: !store.visiblePlaces.isEmpty)
                    Button(store.visiblePlaces.isEmpty ? "添加第一个地点" : "再添加一个地点", systemImage: "plus") { adding = true }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    step("2", "选择自动记录", detail: "开启后先请求使用期间定位；也可以跳过，完全手动记录。", done: location.enabled && location.authorized)
                    Button("开启自动记录") { location.setEnabled(true) }
                        .buttonStyle(.bordered).disabled(store.visiblePlaces.isEmpty || store.isDemo)
                    step("3", "让后台记录继续", detail: "如需锁屏后识别到达和离开，请允许始终定位，并在系统设置开启精确位置。", done: location.authorization == .authorizedAlways)
                    if location.authorization == .authorizedWhenInUse {
                        Button("允许始终定位") { location.requestBackgroundPermission() }.buttonStyle(.bordered)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(location.statusTitle, systemImage: "location.circle")
                            Text(UIApplication.shared.backgroundRefreshStatus == .available ? "系统后台刷新可用" : "系统后台刷新受限，后台记录可能中断")
                            Text("边界防抖需要两次一致位置观测；系统可能延迟投递，重要时间可手动修正。")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let message = location.statusMessage { Text(message).font(.footnote) }
                            Button("检查系统权限") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                    Button("准备好了，开始使用") { complete() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("暂时手动记录，稍后设置") { complete() }.frame(minHeight: 44)
                }.padding(24).frame(maxWidth: 650)
            }.frame(maxWidth: .infinity).pageCanvas()
                .navigationTitle("开始记录").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $adding) { PlaceEditor() }
        }
    }
    private func complete() { if let finish { finish() } else { dismiss() } }
    private func step(_ number: String, _ title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(done ? "✓" : number).font(.headline).frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle()).foregroundStyle(Theme.accent)
                .accessibilityLabel(done ? "已完成" : "第 \(number) 步")
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
