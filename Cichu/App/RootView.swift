import SwiftUI

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView().undoNotice() }.tabItem { Label("今日", systemImage: "sun.horizon") }.tag(0)
            NavigationStack { PlacesView().undoNotice() }.tabItem { Label("地点", systemImage: "map") }.tag(1)
            NavigationStack { ReviewView().undoNotice() }.tabItem { Label("回顾", systemImage: "chart.bar.xaxis") }.tag(2)
            NavigationStack { SettingsView().undoNotice() }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isDemo {
                HStack {
                    Label("示例体验 · 不保存到你的记录", systemImage: "sparkles").font(.caption)
                    Spacer(); Button("退出") { dismiss() }.font(.subheadline.bold()).frame(minHeight: 44)
                }.padding(.horizontal).background(Theme.surface)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded && !store.isDemo }, set: { onboarded = !$0 })) {
            WelcomeView { onboarded = true }
        }
    }
}

struct WelcomeView: View {
    let finish: () -> Void
    @State private var demo = false
    @State private var setup = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                BrandMark().frame(width: 64, height: 64).padding(.top, 32)
                Text("此处").font(.title3.weight(.medium))
                Text("看见时间，\n留在哪里。").font(.system(.largeTitle, design: .rounded).bold())
                Text("把每一次停留，记成自己的时间地图。")
                    .font(.body).foregroundStyle(Theme.quiet).lineSpacing(6)
                Group {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("自动感知常用地点的到达与离开", systemImage: "mappin.and.ellipse")
                        Label("看懂停留、通勤与长期生活变化", systemImage: "clock.arrow.circlepath")
                        Label("无需账号，记录保存在本机", systemImage: "lock.shield")
                    }.font(.subheadline)
                }
                Button { setup = true } label: { Text("开始我的记录").frame(maxWidth: .infinity).padding(12) }
                    .buttonStyle(PrimaryButtonStyle()).controlSize(.large)
                Button("先看看示例") { demo = true }.frame(maxWidth: .infinity, minHeight: 44)
                Text("添加地点后再选择是否开启定位。你也可以始终手动记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 650)
        }.frame(maxWidth: .infinity).pageCanvas()
            .sheet(isPresented: $setup) { SetupGuideView { setup = false; finish() } }
            .fullScreenCover(isPresented: $demo) { DemoHost() }
    }
}
