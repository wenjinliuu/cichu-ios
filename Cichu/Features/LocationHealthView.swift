import SwiftUI
import CoreLocation

struct LocationHealthView: View {
    @Environment(LocationService.self) private var location
    @Environment(JournalStore.self) private var store
    @Environment(\.openURL) private var openURL
    var body: some View {
        Form {
            Section {
                Label(location.statusTitle, systemImage: location.backgroundReady ? "checkmark.circle.fill" : "location.circle")
                    .foregroundStyle(location.backgroundReady ? Theme.color(.exercise) : Theme.accentText)
                Text(location.statusDetail)
                Toggle("自动记录", isOn: Binding(get: { location.enabled }, set: { location.setEnabled($0) })).disabled(store.isDemo)
            }
            Section("权限检查") {
                LabeledContent("定位授权", value: authorizationTitle)
                LabeledContent("精确位置", value: location.accuracyAuthorization == .fullAccuracy ? "已开启" : "未开启")
                LabeledContent("后台刷新", value: UIApplication.shared.backgroundRefreshStatus == .available ? "可用" : "受限")
                if location.authorization == .authorizedWhenInUse { Button("允许全天后台记录") { location.requestBackgroundPermission() } }
                Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            Section("记录检查") {
                LabeledContent("监测常用地点", value: "\(location.monitoredPlaceCount) / 20")
                LabeledContent("最近定位", value: location.lastFixAt?.formatted(date: .abbreviated, time: .shortened) ?? "本次启动尚未获得")
                LabeledContent("最近地点事件", value: (location.lastEventAt ?? store.observations.first?.receivedAt)?.formatted(date: .abbreviated, time: .shortened) ?? "尚未获得")
                Button("立即定位并识别") { if !location.enabled { location.setEnabled(true) } else { location.locateOnce() } }
                    .disabled(store.isDemo).accessibilityIdentifier("location.refresh")
            }
            Section("如何记录") {
                Text("首次开启后，定位到已设地点即可开始记录。围栏识别常用地点的进出，系统访问地点事件补充未命名地点和大概停留时间。")
                Text("锁屏或白天不打开应用也会尝试记录；短停留、相邻店铺、弱信号可能无法准确区分。没有证据的时间保留空白，异常记录可以核对。")
            }
        }.navigationTitle("自动记录检查").scrollContentBackground(.hidden).pageCanvas()
    }
    private var authorizationTitle: String {
        switch location.authorization {
        case .authorizedAlways: "始终允许"
        case .authorizedWhenInUse: "仅使用期间"
        case .denied, .restricted: "不允许"
        default: "尚未授权"
        }
    }
}
