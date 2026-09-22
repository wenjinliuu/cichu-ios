import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance = "system"
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument()
    @State private var erase = false
    @State private var demo = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    BrandMark().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("此处").font(.headline)
                        Text("看见时间，留在哪里。").font(.subheadline).foregroundStyle(Theme.quiet)
                    }
                }.padding(.vertical, 8)
            }
            Section {
                Toggle("自动记录", isOn: Binding(get: { location.enabled }, set: { location.setEnabled($0) })).disabled(store.isDemo)
                LabeledContent("状态", value: location.statusTitle)
                if let status = location.statusMessage { Text(status).font(.footnote).foregroundStyle(.secondary) }
                if location.authorization == .authorizedWhenInUse {
                    Button("允许后台识别地点") { location.requestBackgroundPermission() }
                }
                Button("打开系统权限设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.disabled(store.isDemo)
                DisclosureGroup("记录与权限说明") {
                    Text("后台识别建议允许始终定位及精确位置。省电、信号和强制退出可能中断记录；重要时间可手动调整。暂停会结束当前停留，暂停期间不计入通勤。")
                        .font(.footnote).foregroundStyle(Theme.quiet)
                }
            } header: { Text("记录") }
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                }
            }
            Section {
                LabeledContent("地点", value: "\(store.places.count) 个")
                LabeledContent("时间记录", value: "\(store.entries.count) 段")
                Button("导出完整备份", systemImage: "square.and.arrow.up") {
                    do { document = try store.exportBackup(); exporting = true }
                    catch { message = error.localizedDescription }
                }
                Button("从备份恢复", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(!store.places.isEmpty || !store.entries.isEmpty || store.isDemo)
            } header: { Text("你的数据，由你保管") } footer: {
                Text("备份包含地点坐标，请妥善保管。仅空数据库可恢复；卸载前请备份。")
            }
            Section("开始与检查") {
                NavigationLink("记录设置向导") { SetupGuideView() }
                NavigationLink("核对异常记录") { RecordReviewView() }
            }
            Section("关于") {
                NavigationLink("隐私说明", systemImage: "lock.shield") { PrivacyView() }
                if !store.isDemo { Button("体验示例数据", systemImage: "sparkles") { demo = true } }
                LabeledContent("版本", value: "1.0 · 初始版本")
            }
            Section { Button("清空本机全部记录", role: .destructive) { erase = true } }
        }.navigationTitle("设置").scrollContentBackground(.hidden).pageCanvas()
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "此处备份-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") {
                if case .failure(let error) = $0 { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 50_000_000 else { throw JournalError.invalidBackup }
                    try store.restoreBackup(Data(contentsOf: url)); location.refreshRegions()
                    message = "备份已恢复，自动记录仍保持原来的开关状态。"
                } catch { message = "恢复失败：\(error.localizedDescription)" }
            }
            .confirmationDialog("清空全部地点与时间记录？此操作无法撤销，请先导出备份。", isPresented: $erase, titleVisibility: .visible) {
                Button("永久清空", role: .destructive) { location.setEnabled(false); store.erase() }
            }
            .alert("数据备份", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: { Text(message ?? "") }
            .fullScreenCover(isPresented: $demo) { DemoHost() }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section("记录属于你") { Text("此处无需账号，不接入广告或分析 SDK。地点、停留、移动和备注保存在设备本地，未实现云端同步。") }
            Section("位置权限") { Text("位置用于识别你添加的地点。不会持续收集完整 GPS 行走轨迹。围栏记录受 iOS 调度影响，时间可能延迟。你可随时暂停或在系统设置撤销权限。") }
            Section("地图与搜索") { Text("地图底图、地址和地点搜索由 Apple 地图服务提供，相关请求适用 Apple 的隐私政策。离线时，已有记录仍可查看和编辑。") }
            Section("备份与分享") { Text("只有你主动导出或分享时，应用才把所选内容交给系统文件或分享界面。完整备份包含精确坐标；回顾分享文本不包含地址及坐标。") }
            Section("尚未使用的能力") { Text("此版本不读取屏幕使用时间、照片、健康数据或日历，也不包含支付与订阅。") }
        }.navigationTitle("隐私说明")
    }
}
